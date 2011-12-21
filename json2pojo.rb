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
                :ignore_unknown_properties_annotation, :ignore_unknown_properties_import,
                :json_property_import, :json_serialize_import

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

    #
    # Annotations and imports to put in the Java code based on Jackson.
    # If you want pure POJOs with no annotations, empty these properties.
    #
    self.ignore_unknown_properties_annotation = "@JsonIgnoreProperties(ignoreUnknown = true)"
    self.ignore_unknown_properties_import = "import org.codehaus.jackson.annotate.JsonIgnoreProperties;"

    self.json_property_import = "import org.codehaus.jackson.annotate.JsonProperty;"
    self.json_serialize_import = "import org.codehaus.jackson.map.annotate.JsonSerialize;\n" +
                 "import org.codehaus.jackson.map.annotate.JsonSerialize.Inclusion;"
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
  java_type = "UNKNOWN"
  if value.is_a?(Fixnum)
    java_type = "Long"
  elsif value.is_a?(Float)
    java_type = "Double"
  elsif value.is_a?(Array)
    inner_value = get_java_type(value[0], field_details, key)
    if inner_value == "UNKNOWN"
      inner_value = to_java_class_name(key)
			if @do_chop
			  inner_value.chop!
			end
			setup_data(value[0], key)
			field_details.write_class_file = true
    end
    java_type = "List<" + inner_value + ">"
  elsif value.is_a?(String)
    java_type = "String"
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

def java_class_output(class_name, parent)

  proper_class_name = to_java_class_name(class_name)
  if @java_lists[class_name]
    proper_class_name.chop! if @do_chop
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
      java_field = to_java_field_name(field)
      if @java_fields[field]
        field_type = to_java_class_name(field)
        method_name = to_java_method_name(field_type)
      end
      if (@java_lists[field] and @java_lists[field] == class_name)
        if @field_info[field].array_type
          field_type = @field_info[field].array_type
        elsif @do_chop
          field_type.chop!
        end
        field_type = "List<#{field_type}>"
        list_import = "import java.util.List;"
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
    if current_item == "-t"
      @config.top_level_class = arg_ring.shift
    end
    if current_item == "-l"
      display_features_and_limitations
    end
    if current_item == "-n"
      @do_chop = false
    end
    if current_item == "-h" || current_item == "-?"
      puts <<HELP
Usage:  json2pojo.rb [-h][-?] [-e <json_example_file>] [-c <java_class_file_header>] [-p <java_package_name>] [-o <output_directory>] [-t <top_level_class>] [-n] [-l]

  -h or -?  This help message
  -e        The example JSON file to generate POJOs from. Default: #{@config.json_example_file}
  -c        The text file inserted at the top of every java class generated. Default: #{@config.java_class_file_header}
  -p        Generated java is put in this package.  Default: #{@config.package}
  -o        Output directory for generated java files, which is created if not exists.  Default: #{@config.output_directory}
  -t        The name of the java top level class to be generated.  Default: #{@config.top_level_class}
  -n        Do not chop the last character off names that are arrays/lists.  Default: chop
  -l        Displays current features and limitations with this script.  
HELP
      exit 0
    end
  end
end

def display_features_and_limitations

  puts <<FEATURES_AND_LIMITATIONS
This script, json2pojo, attempts to create java POJOs from example JSON files.  
In general, error handling is pretty woeful, so expect it to crash out with a
stacktrace if you do something bad. :)

There are limits to what can be achieved with automated generation.  This 
script works on a specific subset of JSON.

For example, this will work:

**************************************************************
{
  "foo" : "blah",
  "baz" : 1,
  "xyz" : 2.5
}
**************************************************************

Using the default configuration, the Example java class will be generated in the "output" directory:

**************************************************************
package com.example;




import org.codehaus.jackson.annotate.JsonIgnoreProperties;

/**
 * Created by json2pojo
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class Example {

  private Double xyz;
  private Long baz;
  private String foo;

  public Double getXyz() {
    return xyz;
  }

  public void setXyz(Double xyz) {
    this.xyz = xyz;
  }

  public Long getBaz() {
    return baz;
  }

  public void setBaz(Long baz) {
    this.baz = baz;
  }

  public String getFoo() {
    return foo;
  }

  public void setFoo(String foo) {
    this.foo = foo;
  }

}
**************************************************************

This example will generate code, but it's not very useful:

**************************************************************
{
  "exchange_rates" : 
  {
    "AUD" : 1.234,
    "USD" : 0.998,
    "JPY" : 5.678
  }
}
**************************************************************

ExchangeRates file in "output" directory:
**************************************************************
package com.example;




import org.codehaus.jackson.annotate.JsonIgnoreProperties;

/**
 * Created by json2pojo
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class ExchangeRates {

  private Double AUD;
  private Double USD;
  private Double JPY;

  public Double getAUD() {
    return AUD;
  }
  
  public void setAUD(Double AUD) {
    this.AUD = AUD;
  }

  public Double getUSD() {
    return USD;
  }
  
  public void setUSD(Double USD) {
    this.USD = USD;
  }
  
  public Double getJPY() {
    return JPY;
  }
  
  public void setJPY(Double JPY) {
    this.JPY = JPY;
  }

}
**************************************************************

This script can handle simple arrays of primitives.  It looks at the first entry only
to generate the list in Java.  The following will generate a field as
"private List<Double> simpleNumbers;", etc.

**************************************************************
{
  "simple_numbers" : 
  [
    1.234,
    0.998,
    5.678
  ]
}
**************************************************************

The script can handle arrays that contain objects.  It looks at the first entry only
to generate array objects.  The following works:

**************************************************************
{
  "simple_data" : 
  [
    { "key" : 1.234 },
    { "key" : 3.456 },
    { "key" : 7 }
  ]
}
**************************************************************

Note that if the last value ("key" : 7") was first, then the code generated would be
using Long instead of Double.

Also, by default, the script will chop the last character off array/list names.  In
the above example, the default code generation would create a SimpleDat.java file.
Use -n to override.  If your fields use "nice" plurals, then the default behaviour
generates nice java files.

Using this example:


**************************************************************
{
  "links": [
    {"href":"/example/2342342", "rel":"example", "group":"public"}  
  ]
}
**************************************************************

The files generated by default will be Example.java and Link.java.  The Example
class will contain a List<Link> which is more readble for java purposes.

Fields that are java reserved keywords are not handled in any special manner, so
the code generated will probably fail to compile.

By default, the generated classes are annotated for use with Jackson (see 
http://jackson.codehaus.org/).  Refer to the Configuration in the json2pojo.rb 
file to change this if required.  If you want strict JSON parsing in your java 
application, then clear these properties in the Configuration:

...
self.ignore_unknown_properties_annotation = "@JsonIgnoreProperties(ignoreUnknown = true)"
self.ignore_unknown_properties_import = "import org.codehaus.jackson.annotate.JsonIgnoreProperties;"
...

Finally, feel free to send patches, fixes or suggestions for improving this script.
The code is hack-ish, so apologies for that. :)

Chris
FEATURES_AND_LIMITATIONS

  exit 0
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
    exit -1
  end

  json_file_contents = IO.read(@config.json_example_file)
  json = JSON.parse(json_file_contents)

  @java_classes[@config.top_level_class] = "TOP_LEVEL_CLASS"
  setup_data(json, @config.top_level_class)
  @java_classes.each { |class_name,parent| java_class_output(class_name, parent) }

end
