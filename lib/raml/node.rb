require 'active_support'
require 'active_support/core_ext/class/attribute'
require 'slim'

module Raml
  class Node
    class_attribute :doc_template, :doc_template_compiled

    class << self
      def relative_path(file)
        File.join(
          *File.dirname(__FILE__).
            split(File::SEPARATOR).
            reverse.
            drop_while { |p| p != 'lib' }.
            drop(1).
            reverse,
          'templates',
          file
        )
      end
    end

    attr_reader   :name
    attr_accessor :parent

    def initialize(name, parent)
      @name   = name
      @parent = parent
    end

    def document
      if doc_template
        self.doc_template_compiled ||= Slim::Template.new(doc_template, format: :html5, pretty: true)
        doc_template_compiled.render self
      else
        nil
      end
    end

    private

    def collapse(level, title, display_name=nil, &block)
      @@cid ||= 0
      @@cid  += 1

      @@context_class ||= Struct.new(:cid, :title, :level, :display_name, :content) do
        def highlight_url_params(url)
          url.gsub(/({[^}]+})/, '<span class="url_param">\1</span>')
        end 
      end

      context = @@context_class.new @@cid, title, level, display_name, yield

      @@collapse ||= Slim::Template.new(self.class.relative_path('collapse.slim'), format: :html5, pretty: true)
      @@collapse.render context
    end

    def highlight_url_params(url)
      url.gsub(/({[^}]+})/, '<span class="url_param">\1</span>')
    end 
  end

  class ValueNode < Node
    attr_accessor :value

    def initialize(name, value, parent)
      super name, parent
      @value  = value

      validate_value if respond_to? :validate_value, true
    end
  end

  class PropertiesNode < Node
    class_attribute  :scalar_properties, :non_scalar_properties, :_regexp_property
    self.scalar_properties     = []
    self.non_scalar_properties = []
    self._regexp_property      = nil

    class << self
      def inherit_class_attributes
        self.scalar_properties     = self.scalar_properties.dup
        self.non_scalar_properties = self.non_scalar_properties.dup
      end

      def scalar_property(*properties)
        attr_accessor(*properties.map(&:to_sym))
        _property(scalar_properties, *properties)
      end

      def non_scalar_property(*properties)
        _property(non_scalar_properties, *properties)
      end

      def _property(type, *properties)
        properties.map(&:to_s).each { |prop| type << prop unless type.include? prop }
      end

      def regexp_property(regexp, parse)
        self._regexp_property = [ regexp, parse ]
      end
    end

    def scalar_properties    ; self.class.scalar_properties    ; end
    def non_scalar_properties; self.class.non_scalar_properties; end
    def _regexp_property     ; self.class._regexp_property     ; end 

    attr_accessor :optional
    
    def initialize(name, properties, parent)
      if name.is_a? String and name.end_with? '?'
        allow_optional? parent
        name = name.dup.chomp! '?'
        @optional = true
      else
        @optional = false
      end

      super name, parent

      @children ||= []
      parse_and_validate_props properties
    end

    private

    def allow_optional?(parent)
      until parent == parent.parent or parent.is_a? Root
        return if parent.is_a? Trait::Instance or parent.is_a? ResourceType::Instance
        parent = parent.parent
      end
      raise InvalidProperty, 'Optional properties are only allowed within a trait or resource type specification.'
    end

    def parse_and_validate_props(properties)
      maybe_exec :validate_name
      maybe_exec :validate_parent

      properties.each do |prop_name, prop_value|
        prop_name       = prop_name.to_s
        under_prop_name = Raml.underscore prop_name

        if scalar_properties.include? under_prop_name
          send "#{under_prop_name}=", prop_value
          maybe_exec "validate_#{under_prop_name}"

        elsif non_scalar_properties.include? under_prop_name
          parsed = send "parse_#{under_prop_name}", prop_value
          parsed = [ parsed ] unless parsed.is_a? Array
          @children += parsed

        elsif _regexp_property and _regexp_property[0].match prop_name
          parsed = self.instance_exec(prop_name, prop_value, &_regexp_property[1])
          parsed = [ parsed ] unless parsed.is_a? Array
          @children += parsed

        else
          raise UnknownProperty, "#{prop_name} is an unknown property with value of #{prop_value}."
        end
      end

      validate if respond_to? :validate, true
    end

    def maybe_exec(method, *args)
      send(method,*args) if respond_to? method, true
    end

    def initialize_clone(other)
      super
      @children = @children.clone
      @children.map! do |child|
        child = child.clone
        child.parent = self
        child
      end
    end
  end
end