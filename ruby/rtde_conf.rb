#!/usr/bin/env ruby
require 'rexml/document'
include REXML

module Recipe
  Data = Struct.new(:names, :types)
  def self.parse xmldoc
    rmd = Data.new
    key = XPath.first(xmldoc, "//@key").to_s
    rmd.names = XPath.match(xmldoc, "//field/@name").map {|x| x.to_s }
    rmd.types = XPath.match(xmldoc, "//field/@type").map {|x| x.to_s }
    rmd
  end
end

class ConfigFile
  def initialize(filename)
    @filename = filename
    @dictionary = {}
    @recipes
    xmlfile = File.new @filename
    @recipes= Recipe.parse Document.new(xmlfile)
    puts @recipes
  end

  def get_recipe(key)

    return @recipes.names, @recipes.types
  end
end
