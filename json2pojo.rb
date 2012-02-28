#!/usr/bin/ruby
#
# json2pojo - Generate POJOs from JSON example file, use -h for help message
#
# Copyright (C) 2011  Chris Ryan (chrisr AT rymich.com)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 
require 'rubygems'
require 'json'


#
# Set default values here, some can be overridden on command line
#
class Configuration
  attr_accessor :java_class_file_header, :package, :json_example_file, :top_level_class, 
                :output_directory,
                :unknown_class,
                :ignore_unknown_properties_annotation, :ignore_unknown_properties_import,
                :json_property_import, :json_serialize_import,
                :field_suffix, :field_prefix,
                :class_suffix, :class_prefix

  def initialize
    # File name of text to put at top of file, e.g. author, copyright details, etc
    # Override with -c
    self.java_class_file_header = ""

    # Java package to use
    # Override with -p
    self.package = "com.example"

    # Your example JSON file to generate java from
    # Override with -e
    self.json_example_file = "example.json"

    # The name of the top level Java class to be generated
    # Override with -t
    self.top_level_class = "Example"

    # The output directory for the generated classes
    # Override with -o
    self.output_directory = "output"

    # If types cannot be inferred from example json, they will be represented with Object unless overridden.
    # In which case, UNKNOWN will be used. This will prohibit the class from compiling.
    # Override with -u
    self.unknown_class = "Object"

    #
    # Annotations and imports to put in the Java code based on Jackson.
    # If you want pure POJOs with no annotations, empty these properties.
    #
    self.ignore_unknown_properties_annotation = "@JsonIgnoreProperties(ignoreUnknown = true)"
    self.ignore_unknown_properties_import = "import org.codehaus.jackson.annotate.JsonIgnoreProperties;"

    self.json_property_import = "import org.codehaus.jackson.annotate.JsonProperty;"
    self.json_serialize_import = "import org.codehaus.jackson.map.annotate.JsonSerialize;\n" +
                 "import org.codehaus.jackson.map.annotate.JsonSerialize.Inclusion;"

    self.field_suffix = ""
    self.field_prefix = ""
    self.class_suffix = ""
    self.class_prefix = ""
  end
end

@java_classes = {}
@java_fields = {}
@java_lists = {}
@field_info = {}

class FieldDetails
  attr_accessor :parent, :type, :field_name, :array_type, :write_class_file
end

def get_java_type(value, field_details, key)
  field_details.write_class_file = false
  java_type = @config.unknown_class
  if value.is_a?(Fixnum)
    java_type = "Long"
  elsif value.is_a?(Float)
    java_type = "Double"
  elsif value.is_a?(Array)
    inner_value = get_java_type(value[0], field_details, key)
    if inner_value == @config.unknown_class
      inner_value = to_java_class_name(key)
      if @do_chop
        inner_value.chop!
      end
      inner_value = add_class_prefix_and_suffix(inner_value)
      setup_data(value[0], key)
      field_details.write_class_file = true
    end
    java_type = "List<" + inner_value + ">"
  elsif value.is_a?(String)
    java_type = "String"
  elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
    java_type = "boolean"
  end
  return java_type;
end

def process_array(value, field_details, key, parent)
  field_details.type = "Array"
  @java_classes[key] = parent
  @java_lists[key] = parent
  if value[0].is_a?(Hash)
    setup_data(value[0], key)
  else
    field_details.array_type = get_java_type(value[0], field_details, key)
  end
end

def setup_data(hash, parent) 

  @java_fields[parent] = []
  hash.each do |key,value|
    field_details = FieldDetails.new
    field_details.field_name = key
    field_details.parent = parent
    field_details.write_class_file = true
    if value.is_a?(Array)
      process_array(value, field_details, key, parent)
    elsif value.is_a?(Hash)
      @java_classes[key] = parent
      field_details.type = "Hash"
      setup_data(value, key)
    else
      field_details.type = get_java_type(value, field_details, key)
    end
    @field_info[key] = field_details
    @java_fields[parent] = @java_fields[parent] + [ key ]
  end
 
end


def to_java_class_name(class_name)
  java_class_name = ""
  separator = false
  first = true
  class_name.each_char do |c|
    if separator or first
      java_class_name = java_class_name + c.to_s.upcase
      separator = false
      first = false
    else
      case c
        when '-'
        when '_'
          separator = true
        else
          java_class_name = java_class_name + c
      end
    end
  end
  
  return java_class_name
end


def to_java_field_name(field_name)
  java_field_name = ""
  separator = false
  first = true
  leave_lowercase = false
  if @config.field_prefix != ""
    field_name = @config.field_prefix + "_" + field_name
  end
  if @config.field_suffix != ""
    field_name = field_name + "_" + @config.field_suffix
  end
  field_name.each_char do |c|
    if separator
      if leave_lowercase
        java_field_name = java_field_name + c
      else
        java_field_name = java_field_name + c.to_s.upcase
      end
      separator = false
    else
      case c
        when '-'
        when '_'
            separator = true
            leave_lowercase = false
            if first
              leave_lowercase = true
            end
        else
          java_field_name = java_field_name + c
      end
    end
    first = false
  end
  
  return java_field_name
end


def to_java_method_name(field_name)
  java_method_name = ""
  separator = false
  first = true
  field_name.each_char do |c|
    if separator
      java_method_name = java_method_name + c.to_s.upcase
      separator = false
    else
      case c
        when '-'
        when '_'
            separator = true
        else
          if first
            java_method_name = java_method_name + c.to_s.upcase
          else
            java_method_name = java_method_name + c
          end
      end
    end
    first = false
  end
  
  return java_method_name
end

def write_file(value) 
 
  if value
    return value.write_class_file
  end
  return true
end

def add_class_prefix_and_suffix(class_name)
  if class_name == "String" || class_name == "Double" || class_name == "Long"
    return class_name
  end
  if @config.class_prefix != ""
    class_name = @config.class_prefix + class_name
  end
  if @config.class_suffix != ""
    class_name = class_name + @config.class_suffix
  end
  return class_name
end

def java_class_output(class_name, parent)

  proper_class_name = to_java_class_name(class_name)
  if @java_lists[class_name]
    proper_class_name.chop! if @do_chop
  end
  if class_name != @config.top_level_class
    proper_class_name = add_class_prefix_and_suffix(proper_class_name)
  end

  field_list = ""
  list_import = ""
  json_property_import = ""
  json_serialize_import = ""
  getters_and_setters = ""

  if @java_fields[class_name]
    @java_fields[class_name].each do |field|
      field_type = @field_info[field].type
      method_name = to_java_method_name(field)
      method_name = add_class_prefix_and_suffix(method_name)
      java_field = to_java_field_name(field)
      if @java_fields[field]
        field_type = to_java_class_name(field)
        method_name = to_java_method_name(field_type)
        method_name = add_class_prefix_and_suffix(method_name)
      end
      if (@java_lists[field] and @java_lists[field] == class_name)
        if @field_info[field].array_type
          field_type = @field_info[field].array_type
        elsif @do_chop
          field_type.chop!
        end
        field_type = add_class_prefix_and_suffix(field_type)
        field_type = "List<#{field_type}>"
        list_import = "import java.util.List;"
      else
        field_type = add_class_prefix_and_suffix(field_type)
      end
      json_annotation = ""
      if java_field != field
        json_property_import = @config.json_property_import
        json_annotation = "  @JsonProperty(\"#{field}\")\n"
        if field == '_rev' or field == '_id'
          json_annotation = json_annotation + "  @JsonSerialize(include = Inclusion.NON_EMPTY)\n"
          json_serialize_import = @config.json_serialize_import
        end
      end
      field_list = field_list + json_annotation + "  private #{field_type} #{java_field};\n"
      getters_and_setters = getters_and_setters + <<GS

  public #{field_type} get#{method_name}() {
    return #{java_field};
  }
  
  public void set#{method_name}(#{field_type} #{java_field}) {
    this.#{java_field} = #{java_field};
  }
GS
    end
  end

  doc = <<JCO
#{@java_class_header}
package #@package;

#{list_import}
#{json_property_import}
#{json_serialize_import}
#{@config.ignore_unknown_properties_import}

/**
 * Created by json2pojo
 */
#{@config.ignore_unknown_properties_annotation}
public class #{proper_class_name} \{

#{field_list}
#{getters_and_setters}
\}
JCO

  Dir.mkdir(@config.output_directory) if !File.exists?(@config.output_directory)

  if !File.directory?(@config.output_directory)
    puts "#{@config.output_directory} is not a directory!"
    exit -1
  end

  # don't write java file files "primitive" array/list fields
  if write_file(@field_info[class_name]) == true
    File.open("#{@config.output_directory}/#{proper_class_name}.java", 'w') {|f| f.write(doc) }
  end 

end

# Simplistic parse command line args and override config
def parse_args args
  arg_ring = args.clone
  while arg_ring.length > 0
    current_item = arg_ring.shift
    if current_item == "-e"
      @config.json_example_file = arg_ring.shift
    end
    if current_item == "-p"
      @config.package = arg_ring.shift
    end
    if current_item == "-c"
      @config.java_class_file_header = arg_ring.shift
    end
    if current_item == "-o"
      @config.output_directory = arg_ring.shift
    end
    if current_item == "-u"
      @config.unknown_class = "UNKNOWN"
    end
    if current_item == "-t"
      @config.top_level_class = arg_ring.shift
    end
    if current_item == "-fs"
      @config.field_suffix = arg_ring.shift
    end
    if current_item == "-fp"
      @config.field_prefix = arg_ring.shift
    end
    if current_item == "-cs"
      @config.class_suffix = arg_ring.shift
    end
    if current_item == "-cp"
      @config.class_prefix = arg_ring.shift
    end
    if current_item == "-n"
      @do_chop = false
    end
    if current_item == "-h" || current_item == "-?"
      puts <<HELP
Usage:  json2pojo.rb [-h][-?] [-e <json_example_file>] [-c <java_class_file_header>] [-p <java_package_name>] [-o <output_directory>] [-u] [-t <top_level_class>] [-n] [-fs <field_suffix>] [-fp <field_prefix>] [-cs <class_suffix>] [-cp <class_prefix>]

  -h or -?  This help message
  -e        The example JSON file to generate POJOs from. Default: #{@config.json_example_file}
  -c        The text file inserted at the top of every java class generated. Default: #{@config.java_class_file_header}
  -p        Generated java is put in this package.  Default: #{@config.package}
  -o        Output directory for generated java files, which is created if not exists.  Default: #{@config.output_directory}
  -u        Use UNKNOWN for types that cannot be inferred.  If set, unknown types will prohibit the parent class from compiling. Default: #{@config.unknown_class}
  -t        The name of the java top level class to be generated.  Default: #{@config.top_level_class}
  -n        Do not chop the last character off names that are arrays/lists.  Default: chop
  -fs       Add the supplied value as the suffix to field name.  Default: none
  -fp       Add the supplied value as the prefix to field name.  Default: none
  -cs       Add the supplied value as the suffix to class name.  Default: none
  -cp       Add the supplied value as the prefix to class name.  Default: none
HELP
      exit 0
    end
  end
end


if __FILE__ == $PROGRAM_NAME

  @do_chop = true
  @config = Configuration.new

  parse_args($*)
  puts "Using JSON example file: #{@config.json_example_file}"
  puts "Using Java class file header: #{@config.java_class_file_header}"
  puts "Using Java package: #{@config.package}"
  puts "Using Java top level class: #{@config.top_level_class}"
  puts "Using output directory: #{@config.output_directory}"

  @java_class_header = IO.read(@config.java_class_file_header) if @config.java_class_file_header && File.exists?(@config.java_class_file_header)
  @package = @config.package

  if !File.exists?(@config.json_example_file)
    puts "JSON example file: #{@config.json_example_file} does not exist!"
    puts "Try -h flag for help"
    exit -1
  end

  json_file_contents = IO.read(@config.json_example_file)
  json = JSON.parse(json_file_contents)

  @java_classes[@config.top_level_class] = "TOP_LEVEL_CLASS"
  setup_data(json, @config.top_level_class)
  @java_classes.each { |class_name,parent| java_class_output(class_name, parent) }

end
