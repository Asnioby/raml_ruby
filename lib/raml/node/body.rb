module Raml
  class Body < PropertiesNode
    inherit_class_attributes
    
    include Global
    include Merge
    include Parent
    include Validation

    MEDIA_TYPE_RE = %r{[a-z\d][-\w.+!#$&^]{0,63}/[a-z\d][-\w.+!#$&^]{0,63}(;.*)?}oi

    scalar_property     :example 
    non_scalar_property :form_parameters, :schema

    alias_method :media_type, :name
    
    self.doc_template = relative_path 'body.slim'
    
    children_by :form_parameters, :name, Parameter::FormParameter
    
    child_of :schema, [ Schema, SchemaReference ]

    def web_form?
      [ 'application/x-www-form-urlencoded', 'multipart/form-data' ].include? media_type
    end
    
    def merge(other)
      raise MergeError, "Media types don't match." if media_type != other.media_type
      
      super

      merge_properties other, :form_parameters

      if other.schema
        @children.delete_if { |c| [ Schema, SchemaReference ].include? c.class } if schema
        @children << other.schema
      end

      self
    end

    private
    
    def validate_name
      raise InvalidMediaType, 'body media type is invalid' unless media_type =~ Body::MEDIA_TYPE_RE
    end

    def parse_form_parameters(value)
      validate_hash 'formParameters', value, String, Hash

      value.map do |name, form_parameter_data|
        Parameter::FormParameter.new name, form_parameter_data, self
      end
    end

    def parse_schema(value)
      validate_string :schema, value

      if schema_declarations.include? value
        SchemaReference.new value, self
      else
        Schema.new '_', value, self
      end
    end

    def validate
      if web_form?
        raise InvalidProperty, 'schema property can\'t be defined for web forms.' if schema
        raise RequiredPropertyMissing, 'formParameters property must be specified for web forms.' if
          form_parameters.empty?
      end
    end
  end
end
