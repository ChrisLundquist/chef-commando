# Author:: Bryan W. Berry (<bryan.berry@gmail.com>)
# Author:: Daniel DeLeo (<dan@kallistec.com>)
# Copyright:: Copyright (c) 2012 Bryan W. Berry
# Copyright:: Copyright (c) 2012 Daniel DeLeo
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'chef'
require 'chef/application'
require 'chef/client'
require 'chef/config'
require 'chef/log'
require 'fileutils'
require 'tempfile'
require 'chef/providers'
require 'chef/resources'

class Chef::Application::Commando < Chef::Application

  banner "Usage: chef-commando [RECIPE_FILE] [-e RECIPE_TEXT] [-s] [-c CONFIG] [-j JSON]"

  option :config_file,
    :short => "-c CONFIG",
    :long  => "--config CONFIG",
    :default => Chef::Config.platform_specfic_path('/etc/chef/solo.rb'),
    :description => "The configuration file to use"

  option :execute,
    :short        => "-e RECIPE_TEXT",
    :long         => "--execute RECIPE_TEXT",
    :description  => "Execute resources supplied in a string",
    :proc         => nil

  option :json_attribs,
    :short => "-j JSON_ATTRIBS",
    :long => "--json-attributes JSON_ATTRIBS",
    :description => "Load attributes from a JSON file or URL",
    :proc => nil

  option :stdin,
    :short        => "-s",
    :long         => "--stdin",
    :description  => "Execute resources read from STDIN",
    :boolean      => true

  option :log_level,
    :short        => "-l LEVEL",
    :long         => "--log_level LEVEL",
    :description  => "Set the log level (debug, info, warn, error, fatal)",
    :default      => :error # Don't print the run_list [] stuff, we know that.
    :proc         => lambda { |l| l.to_sym }

  option :help,
    :short        => "-h",
    :long         => "--help",
    :description  => "Show this message",
    :on           => :tail,
    :boolean      => true,
    :show_options => true,
    :exit         => 0

  option :version,
    :short        => "-v",
    :long         => "--version",
    :description  => "Show chef version",
    :boolean      => true,
    :proc         => lambda {|v| puts "Chef: #{::Chef::VERSION}"},
  :exit         => 0

  option :why_run,
    :short        => '-W',
    :long         => '--why-run',
    :description  => 'Enable whyrun mode',
    :boolean      => true

  def initialize
    super
  end

  def reconfigure
    parse_config_file
    parse_json_attribs
    configure_logging
  end

  def read_recipe_file(file_name)
    recipe_path = file_name
    unless File.exist?(recipe_path)
      Chef::Application.fatal!("No file exists at #{recipe_path}", 1)
    end
    recipe_path = File.expand_path(recipe_path)
    recipe_fh = open(recipe_path)
    recipe_text = recipe_fh.read
    [recipe_text, recipe_fh]
  end

  def get_recipe_and_run_context
    Chef::Config[:solo] = true

    cl = Chef::CookbookLoader.new(Chef::Config[:cookbook_path])
    cl.load_cookbooks
    cookbook_collection = Chef::CookbookCollection.new(cl)

    @chef_client = Chef::Client.new
    @chef_client.run_ohai
    @chef_client.load_node
    @chef_client.build_node

    node = @chef_client.node

    @events = Chef::EventDispatch::Dispatcher.new()
    node.run_context = Chef::RunContext.new(node, cookbook_collection, @events)
    node.run_list = Chef::RunList.new(@chef_client_json["run_list"].join(","))
    node.run_context.load(node.expand!)

    run_context = if @chef_client.events.nil?
                    Chef::RunContext.new(@chef_client.node, cookbook_collection)
                  else
                    Chef::RunContext.new(@chef_client.node, cookbook_collection, @chef_client.events)
                  end
    recipe = Chef::Recipe.new("(chef-apply cookbook)", "(chef-apply recipe)", run_context)
    [recipe, run_context]
  end

  # write recipe to temp file, so in case of error,
  # user gets error w/ context
  def temp_recipe_file
    @recipe_fh = Tempfile.open('recipe-temporary-file')
    @recipe_fh.write(@recipe_text)
    @recipe_fh.rewind
    @recipe_filename = @recipe_fh.path
  end

  def run_chef_recipe
    if config[:execute]
      @recipe_text = config[:execute]
      temp_recipe_file
    elsif config[:stdin]
      @recipe_text = STDIN.read
      temp_recipe_file
    else
      @recipe_filename = ARGV[0]
      @recipe_text,@recipe_fh = read_recipe_file @recipe_filename
    end
    recipe,run_context = get_recipe_and_run_context
    recipe.instance_eval(@recipe_text, @recipe_filename, 1)
    runner = Chef::Runner.new(run_context)
    begin
      runner.converge
    ensure
      @recipe_fh.close
    end
  end

  def run_application
    begin
      parse_options
      run_chef_recipe
      Chef::Application.exit! "Exiting", 0
    rescue SystemExit => e
      raise
    rescue Exception => e
      Chef::Application.debug_stacktrace(e)
      Chef::Application.fatal!("#{e.class}: #{e.message}", 1)
    end
  end

  # Get this party started
  def run
    reconfigure
    run_application
  end

  private

  def parse_json_attribs
    if Chef::Config[:json_attribs]
      begin
        json_io = case Chef::Config[:json_attribs]
                  when /^(http|https):\/\//
                    @rest = Chef::REST.new(Chef::Config[:json_attribs], nil, nil)
                    @rest.get_rest(Chef::Config[:json_attribs], true).open
                  else
                    open(Chef::Config[:json_attribs])
                  end
      rescue SocketError => error
        Chef::Application.fatal!("I cannot connect to #{Chef::Config[:json_attribs]}", 2)
      rescue Errno::ENOENT => error
        Chef::Application.fatal!("I cannot find #{Chef::Config[:json_attribs]}", 2)
      rescue Errno::EACCES => error
        Chef::Application.fatal!("Permissions are incorrect on #{Chef::Config[:json_attribs]}. Please chmod a+r #{Chef::Config[:json_attribs]}", 2)
      rescue Exception => error
        Chef::Application.fatal!("Got an unexpected error reading #{Chef::Config[:json_attribs]}: #{error.message}", 2)
      end

      begin
        @chef_client_json = Chef::JSONCompat.from_json(json_io.read)
        json_io.close unless json_io.closed?
      rescue JSON::ParserError => error
        Chef::Application.fatal!("Could not parse the provided JSON file (#{Chef::Config[:json_attribs]})!: " + error.message, 2)
      end
    end
  end

  # Parse the configuration file
  def parse_config_file
    parse_options

    begin
      case config[:config_file]
      when /^(http|https):\/\//
        Chef::REST.new("", nil, nil).fetch(config[:config_file]) { |f| apply_config(f.path) }
      else
        ::File::open(config[:config_file]) { |f| apply_config(f.path) }
      end
    rescue Errno::ENOENT => error
      Chef::Log.warn("*****************************************")
      Chef::Log.warn("Did not find config file: #{config[:config_file]}, using command line options.")
      Chef::Log.warn("*****************************************")

      Chef::Config.merge!(config)
    rescue SocketError => error
      Chef::Application.fatal!("Error getting config file #{Chef::Config[:config_file]}", 2)
    rescue Chef::Exceptions::ConfigurationError => error
      Chef::Application.fatal!("Error processing config file #{Chef::Config[:config_file]} with error #{error.message}", 2)
    rescue Exception => error
      Chef::Application.fatal!("Unknown error processing config file #{Chef::Config[:config_file]} with error #{error.message}", 2)
    end
  end
end
