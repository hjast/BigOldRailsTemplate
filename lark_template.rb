require 'open-uri'
require 'yaml'
require 'base64'

TEMPLATE_PATH = "/Users/reubendoetsch/Sites/BigOldRailsTemplate/CodeFragments"

 
# Utility Methods
 
# download, from_repo, and commit_state methods swiped from 
# http://github.com/Sutto/rails-template/blob/07b044072f3fb0b40aea27b713ca61515250f5ec/rails_template.rb
 
def download(from, to = from.split("/").last)
  #run "curl -s -L #{from} > #{to}"
  file to, open(from).read
rescue
  puts "Can't get #{from} - Internet down?"
  exit!
end
 
def from_repo(github_user, from, to = from.split("/").last)
  download("http://github.com/#{github_user}/rails-template/raw/master/#{from}", to)
end

#This methods reads a file from either the file system or repo to get 
def file_from(path_name, binding_var, filename=nil, from_repo = false, github_user = nil, custom_url = nil)
  filename=File.basename(path_name) if filename==nil
  filePath = File.join(TEMPLATE_PATH,filename)
  puts filePath.inspect
  puts File.exist? filePath
  #str=IO.read(filePath).gsub('"','\\"')
  str = eval('"'+IO.read(filePath).gsub('"','\\"')+'"',binding_var)
  file path_name, str
end
    
 
def commit_state(comment)
  git :add => "."
  git :commit => "-am '#{comment}'"
end

# grab an arbitrary file from github
def file_from_repo(github_user, repo, sha, filename, to = filename)
  download("http://github.com/#{github_user}/#{repo}/raw/#{sha}/#{filename}", to)
end

# Piston and braid methods out of my own head
# sudo gem install piston on your dev box before using these
# Piston locking support with git requires Piston 2.0.3+
# Piston branch management with git 1.6.3 requires Piston 2.0.5+

# Use Piston to install and lock a plugin:
# piston_plugin 'stuff', :git => 'git://github.com/whoever/stuff.git'
# Use Piston to install a plugin without locking:
# piston_plugin 'stuff', :git => 'git://github.com/whoever/stuff.git', :lock => false
def piston_plugin(name, options={})
  lock = options.fetch(:lock, true)
  
  if options[:git] || options[:svn]
    in_root do
      run("piston import #{options[:svn] || options[:git]} vendor/plugins/#{name}")
      run("piston lock vendor/plugins/#{name}") if lock
      commit_state("Added pistoned #{name}")
    end
    log "plugin installed #{'and locked ' if lock}with Piston:", name
  else
    log "! no git or svn provided for #{name}.  skipping..."
  end
end

# Use Piston to install and lock current Rails edge (master):
# piston_rails
# Use Piston to install but not lock current Rails edge (master):
# piston_rails :lock => false
# Use Piston to install and lock edge of a specific Rails branch:
# piston_rails :branch => "2-3-stable"
# Use Piston to install but not lock edge of a specific Rails branch:
# piston_rails, :branch => "2-3-stable", :lock => false
def piston_rails(options={})
  lock = options.fetch(:lock, true)

  if options[:branch]
    in_root do
      run("piston import --commit #{options[:branch]} git://github.com/rails/rails.git vendor/rails")
      commit_state("Added pistoned Rails using the edge of the #{options[:branch]} branch")
      if lock
        run("piston lock vendor/rails")
        commit_state("Locked pistoned rails")
      end
    end
  else
    in_root do
      run("piston import git://github.com/rails/rails.git vendor/rails")
      commit_state("Added pistoned Rails edge")
      if lock
        run("piston lock vendor/rails")
        commit_state("Locked pistoned rails")
      end
    end
  end
  
  log "rails installed #{'and locked ' if lock}with Piston", options[:branch]
end

# braid support is experimental and largely untested
def braid_plugin(name, options={})
  if options[:git]
    in_root do
      run("braid add -p #{options[:git]}")
      commit_state("Added braided #{name}")
    end
    log "plugin installed with Braid:", name
  else
    log "! no git provided for #{name}.  skipping..."
  end
end

def braid_rails(options={})
  if options[:branch]
    log "! branch support for Braid is not yet implemented"
  else
    in_root do
      run("braid add git://github.com/rails/rails.git vendor/rails")
      log "rails installed with Braid"
    end
  end
end

# cloning rails is experimental and somewhat untested
def clone_rails(options={})
  if options[:submodule]
    in_root do
      if options[:branch] && options[:branch] != "master"
        git :submodule => "add git://github.com/rails/rails.git vendor/rails -b #{options[:branch]}"
      else
        git :submodule => "add git://github.com/rails/rails.git vendor/rails"
      end
    end
  else
    inside 'vendor' do
      run('git clone git://github.com/rails/rails.git')
    end
    if options[:branch] && options[:branch] != "master"
      inside 'vendor/rails' do
        run("git branch --track #{options[:branch]} origin/#{options[:branch]}")
        run("git checkout #{options[:branch]}")
      end
    end
  end
  
  log "rails installed #{'and submoduled ' if options[:submodule]}from GitHub", options[:branch]
end

# update rails bits in application after vendoring a new copy of rails
# we need to do this the hard way because we want to overwrite without warning
# TODO: Can we introspect the actual rake:update task to get a current list of subtasks?
def update_app
  in_root do
    run("echo 'a' | rake rails:update:scripts")
    run("echo 'a' | rake rails:update:javascripts")
    run("echo 'a' | rake rails:update:configs")
    run("echo 'a' | rake rails:update:application_controller")

    if @javascript_library != "prototype"
      run "rm public/javascripts/controls.js"
      run "rm public/javascripts/dragdrop.js"
      run "rm public/javascripts/effects.js"
      run "rm public/javascripts/prototype.js"
    end
  end
end

current_app_name = File.basename(File.expand_path(root))

# Option set-up
begin
  template_options = {}
  template_paths = [
                    File.expand_path(File.join(ENV['HOME'],'.big_old_rails_template')),
                    File.expand_path(File.dirname(template), File.join(root,'..'))
                   ]

  template_paths.each do |template_path|
    template = File.join(template_path, "config.yml")
    next unless File.exists? template

    open(template) do |f|
      template_options = YAML.load(f)
    end
    # Config loaded, stop searching
    break if template_options
  end
rescue
end

rails_branch = template_options["rails_branch"]
rails_branch = "2-3-stable" if rails_branch.nil?

database = template_options["database"].nil? ? ask("Which database? postgresql (default), mysql, sqlite").downcase : template_options["database"]
database = "postgresql" if database.nil?

exception_handling = template_options["exception_handling"].nil? ? ask("Which exception reporting? exceptional (default), hoptoad").downcase : template_options["exception_handling"]
exception_handling = "exceptional" if exception_handling.nil?

monitoring = template_options["monitoring"].nil? ? ask("Which monitoring? new_relic (default), scout").downcase : template_options["monitoring"]
monitoring = "new_relic" if monitoring.nil?

@branch_management = template_options["branch_management"].nil? ? ask("Which branch management? piston (default), braid, git, none").downcase : template_options["branch_management"]
@branch_management = "piston" if @branch_management.nil?

rails_strategy = template_options["rails_strategy"].nil? ? ask("Which Rails strategy? vendored (default), gem").downcase : template_options["rails_strategy"]
rails_strategy = "vendored" if rails_strategy.nil?

link_rails_root = template_options["link_rails_root"]
link_rails_root = "~/rails" if link_rails_root.nil?

ie6_blocking = template_options["ie6_blocking"].nil? ? ask("Which IE 6 blocking? none, light (default), ie6nomore").downcase : template_options["ie6_blocking"]
ie6_blocking = "light" if ie6_blocking.nil?

@javascript_library = template_options["javascript_library"].nil? ? ask("Which javascript library? prototype (default), jquery").downcase : template_options["javascript_library"]
@javascript_library = "prototype" if @javascript_library.nil?

design = template_options["design"].nil? ? ask("Which design? none (default), bluetrip").downcase : template_options["design"]
design = "none" if design.nil?

smtp_address = template_options["smtp_address"]
smtp_domain = template_options["smtp_domain"]
smtp_username = template_options["smtp_username"]
smtp_password = template_options["smtp_password"]
capistrano_user = template_options["capistrano_user"]
capistrano_repo_host = template_options["capistrano_repo_host"]
capistrano_production_host = template_options["capistrano_production_host"]
capistrano_staging_host = template_options["capistrano_staging_host"]
exceptional_api_key = template_options["exceptional_api_key"]
hoptoad_api_key = template_options["hoptoad_api_key"]
newrelic_api_key = template_options["newrelic_api_key"]
notifier_email_from = template_options["notifier_email_from"]
default_url_options_host = template_options["default_url_options_host"]

def install_plugin (name, options)
  case @branch_management
  when 'none'
    plugin name, options
  when 'piston'
    piston_plugin name, options
  when 'braid'
    braid_plugin name, options
  when 'git'
    plugin name, options.merge(:submodule => true)
  end
end

def install_rails (options)
  case @branch_management
  when 'none'
    clone_rails options
  when 'piston'
    piston_rails options
  when 'braid'
    braid_rails options
  when 'git'
    clone_rails options.merge(:submodule => true)
  end
end

# Actual application generation starts here

# Delete unnecessary files
run "rm README"
run "rm public/index.html"
run "rm public/favicon.ico"

# Set up git repository
# must do before running piston or braid
git :init

# Set up gitignore and commit base state
file_from '.gitignore', binding

commit_state "base application"

# plugins
plugins = 
  {
    'admin_data' => {:options => {:git => 'git://github.com/neerajdotname/admin_data.git'}},
    'db_populate' => {:options => {:git => 'git://github.com/ffmike/db-populate.git'}},
    'exceptional' => {:options => {:git => 'git://github.com/contrast/exceptional.git'},
                      :if => 'exception_handling == "exceptional"'},
    'fast_remote_cache' => {:options => {:git => 'git://github.com/37signals/fast_remote_cache.git'}},
    'hashdown' => {:options => {:git => 'git://github.com/rubysolo/hashdown.git'}},
    'hoptoad_notifier' => {:options => {:git => 'git://github.com/thoughtbot/hoptoad_notifier.git'},
                           :if => 'exception_handling == "hoptoad"'},
    'live_validations' => {:options => {:git => 'git://github.com/augustl/live-validations.git'}},
    'new_relic' => {:options => {:git => 'git://github.com/newrelic/rpm.git'},
                    :if => 'monitoring == "new_relic"'},
    'object_daddy' => {:options => {:git => 'git://github.com/flogic/object_daddy.git'}},
    'paperclip' => {:options => {:git => 'git://github.com/thoughtbot/paperclip.git'}},
    'parallel_specs' => {:options => {:git => 'git://github.com/grosser/parallel_specs.git'}},
    'rack-bug' => {:options => {:git => 'git://github.com/brynary/rack-bug.git'}},
    'rubaidhstrano' => {:options => {:git => 'git://github.com/rubaidh/rubaidhstrano.git'}},
    'scout_rails_instrumentation' => {:options => {:git => 'git://github.com/highgroove/scout_rails_instrumentation.git'},
                                      :if => 'monitoring == "scout"'},
    'shmacros' => {:options => {:git => 'git://github.com/maxim/shmacros.git'}},
    'stringex' => {:options => {:git => 'git://github.com/rsl/stringex.git'}},
    'superdeploy' => {:options => {:git => 'git://github.com/saizai/superdeploy.git'}},
    'time-warp' => {:options => {:git => 'git://github.com/iridesco/time-warp.git'}},    
    'validation_reflection' => {:options => {:git => 'git://github.com/redinger/validation_reflection.git'}}    
  }
  
plugins.each do |name, value|
  if  value[:if].nil? || eval(value[:if])
    install_plugin name, value[:options]
  end
end
  
# gems
gem 'authlogic',
  :version => '~> 2.0'
gem 'mislav-will_paginate', 
  :version => '~> 2.2', 
  :lib => 'will_paginate',
  :source => 'http://gems.github.com'
gem 'jscruggs-metric_fu', 
  :version => '~> 1.1', 
  :lib => 'metric_fu', 
  :source => 'http://gems.github.com' 
gem "binarylogic-searchlogic",
  :lib     => 'searchlogic',
  :source  => 'http://gems.github.com',
  :version => '~> 2.0'
gem "justinfrench-formtastic", 
  :lib     => 'formtastic', 
  :source  => 'http://gems.github.com'
  
# development only
gem "cwninja-inaction_mailer", 
  :lib => 'inaction_mailer/force_load', 
  :source => 'http://gems.github.com', 
  :env => 'development'
gem "ffmike-query_trace",
  :lib => 'query_trace', 
  :source => 'http://gems.github.com',
  :env => 'development'

# test only
gem "ffmike-test_benchmark", 
  :lib => 'test_benchmark', 
  :source => 'http://gems.github.com',
  :env => 'test'
gem "webrat",
  :env => "test"

# assume gems are already on dev box, so don't install    
# rake("gems:install", :sudo => true)

commit_state "Added plugins and gems"

# environment updates
in_root do
  run 'cp config/environments/production.rb config/environments/staging.rb'
end
environment 'config.middleware.use "Rack::Bug"', :env => 'development'
environment 'config.middleware.use "Rack::Bug"', :env => 'staging'

commit_state "Set up staging environment and hooked up Rack::Bug"

# make sure HAML files get searched if we go that route
file '.ackrc', <<-END
--type-set=haml=.haml
END

# some files for app
if @javascript_library == "prototype"
  download "http://livevalidation.com/javascripts/src/1.3/livevalidation_prototype.js", "public/javascripts/livevalidation.js"
elsif @javascript_library == "jquery"
  file_from_repo "ffmike", "jquery-validate", "master", "jquery.validate.min.js", "public/javascripts/jquery.validate.min.js"
end

if design == "bluetrip"
  inside('public') do
    run('mkdir img')
  end
  inside('public/img') do
    run('mkdir icons')
  end
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "css/ie.css", "public/stylesheets/ie.css"
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "css/print.css", "public/stylesheets/print.css"
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "css/screen.css", "public/stylesheets/screen.css"
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "css/style.css", "public/stylesheets/style.css"
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "img/grid.png", "public/img/grid.png"
  %w(cross doc email external feed im information key pdf tick visited xls).each do |icon|
    file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "img/icons/#{icon}.png", "public/img/icons/#{icon}.png"
  end
end

if design == "bluetrip"
  flash_class = "span-22 prefix-1 suffix-1 last"
end

file 'app/views/layouts/_flashes.html.erb', <<-END
<div id="flash" class="#{flash_class}">
  <% flash.each do |key, value| -%>
    <div id="flash_<%= key %>" class="<%= key %>"><%=h value %></div>
  <% end -%>
</div>
END

if @javascript_library == "prototype"
  javascript_include_tags = '<%= javascript_include_tag :defaults, "livevalidation", :cache => true %>'
else @javascript_library
  javascript_include_tags = '<%= javascript_include_tag "http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js", "http://ajax.googleapis.com/ajax/libs/jqueryui/1.7.2/jquery-ui.min.js" %><%= javascript_include_tag "jquery.validate.min.js", "application", :cache => true  %>'
end

if design == "bluetrip"
  extra_stylesheet_tags = <<-END
  <%= stylesheet_link_tag 'screen', :media => 'screen, projection', :cache => true %>
  <%= stylesheet_link_tag 'print', :media => 'print', :cache => true %>
  <!--[if IE]>
    <%= stylesheet_link_tag 'ie', :media => 'screen, projection', :cache => true %>
  <![endif]-->
  <%= stylesheet_link_tag 'style', :media => 'screen, projection', :cache => true %>
END
  footer_class = "span-24 small quiet"
else
  extra_stylesheet_tags= ""
  footer_class=""
end
file_from 'app/views/layouts/application.html.erb', binding

# rakefile for use with inaction_mailer
rakefile 'mail.rake', <<-END
namespace :mail do
  desc "Remove all files from tmp/sent_mails"
  task :clear do
    FileList["tmp/sent_mails/*"].each do |mail_file|
      File.delete(mail_file)
    end
  end
end
END

if design == "bluetrip"
  application_styles = <<-END

  /* @group Application Styles */

  body {
  	background-color: #ccff99;
  }

  .container {
  	background-color: white;
  }

  #top_menu {
  	text-align: right;
  }

  #left_menu ul {
  	margin: 0;
  	padding: 0;
  	list-style-type: none;
  }

  #left_menu ul a {
  	display: block;
  	width: 150px;
  	height: 20px;
  	line-height: 40px;
  	text-decoration: none;	
  }

  #left_menu li {

  }

  #footer {
  	margin-top: 15px;
  	margin-bottom: 10px;
  	text-align: center;
  }

  /* @end */
END
else
  application_styles=""
end

file_from 'public/stylesheets/application.css', binding

generate(:formtastic_stylesheets)

file_from 'app/controllers/application_controller.rb', binding

file_from 'app/helpers/application_helper.rb', binding

# initializers
initializer 'requires.rb', <<-END
Dir[File.join(RAILS_ROOT, 'lib', '*.rb')].each do |f|
  require f
end
END

initializer 'admin_data.rb', <<-END
ADMIN_DATA_VIEW_AUTHORIZATION = Proc.new { |controller| controller.send("admin_logged_in?") }
ADMIN_DATA_UPDATE_AUTHORIZATION = Proc.new { |controller| return false }
END

if @javascript_library == "jquery"
  initializer 'live_validations.rb', <<-END
LiveValidations.use :jquery_validations, :default_valid_message => "", :validate_on_blur => true
END
elsif @javascript_library == "prototype"
  initializer 'live_validations.rb', <<-END
LiveValidations.use :livevalidation_dot_com, :default_valid_message => "", :validate_on_blur => true
END
end

base64_user_name = Base64.encode64(smtp_username) unless smtp_username.blank? 
base64_password = Base64.encode64(smtp_password) unless smtp_username.blank? 

initializer 'mail.rb', <<-END
ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.smtp_settings = {
  :address => "#{smtp_address}",
  :port => 25,
  :domain => "#{smtp_domain}",
  :authentication => :login,
  :user_name => "#{smtp_username}",
  :password => "#{smtp_password}"  
}

# base64 encodings - useful for manual SMTP testing:
# username => #{base64_user_name}
# password => #{base64_password}
END

initializer 'date_time_formats.rb', <<-END
ActiveSupport::CoreExtensions::Time::Conversions::DATE_FORMATS.merge!(
  :us => '%m/%d/%y',
  :us_with_time => '%m/%d/%y, %l:%M %p',
  :short_day => '%e %B %Y',
  :long_day => '%A, %e %B %Y'
)

Date::DATE_FORMATS[:human] = "%B %e, %Y"
END

initializer 'query_trace.rb', <<-END
# Turn on query tracing output; requires server restart
# QueryTrace.enable!
END

initializer 'backtrace_silencers.rb', <<-END
# Be sure to restart your server when you modify this file.

# You can add backtrace silencers for libraries that you're using but don't wish to see in your backtraces.
# Rails.backtrace_cleaner.add_silencer { |line| line =~ /my_noisy_library/ }

# You can also remove all the silencers if you're trying do debug a problem that might steem from framework code.
# Rails.backtrace_cleaner.remove_silencers!

Rails.backtrace_cleaner.add_silencer { |line| line =~ /haml/ }
END

commit_state "application files and initializers"

# deployment
capify!

file_from 'config/deploy.rb', binding

file 'config/deploy/production.rb', <<-END
set :host, "#{capistrano_production_host}"
set :branch, "master"
END

file 'config/deploy/staging.rb', <<-END
set :host, "#{capistrano_staging_host}"
set :branch, "staging"
END

commit_state "deployment files"

# error handling
if exception_handling == "exceptional"
  file_from 'config/exceptional.yml', binding
end

if exception_handling == "hoptoad"
  initializer 'hoptoad.rb', <<-END
HoptoadNotifier.configure do |config|
  config.api_key = '#{hoptoad_api_key}'
end
END
end

# performance monitoring
if monitoring == "new_relic"
  file_from 'config/newrelic.yml', binding
end

if monitoring == "scout"
  file_from 'config/scout.yml', binding
end

# database
if database == "mysql"
  file_from 'config/database.yml', binding, "database_mysql.yml"
elsif database == "sqlite"
  file_from 'config/database.yml', binding, "database_sqlite.yml"
else # database defaults to postgresql
  file_from 'config/database.yml', binding, "database_postgre.yml"
end

file 'db/populate/01_sample_seed.rb', <<-END
# Model.create_or_update(:id => 1, :name => 'sample')
# User db/populate/development/01_file.rb for development-only data
END

commit_state "configuration files"

# testing
file_from 'test/exemplars/sample_exemplar.rb', binding

file_from 'test/test_helper.rb', binding

file_from 'test/unit/notifier_test.rb', binding

file_from 'test/unit/user_test.rb', binding

file_from 'test/shoulda_macros/authlogic.rb', binding

file_from 'test/shoulda_macros/filter.rb', binding

file_from 'test/shoulda_macros/helpers.rb', binding

file_from 'test/exemplars/user_exemplar.rb', binding

file_from 'test/unit/user_session_test.rb', binding

file_from 'test/unit/helpers/application_helper_test.rb', binding

file_from 'test/functional/accounts_controller_test.rb', binding

file_from 'test/functional/application_controller_test.rb', binding

file_from 'test/functional/users_controller_test.rb', binding

file_from 'test/functional/user_sessions_controller_test.rb', binding

if ie6_blocking == 'light'
  upgrade_test = ", :upgrade => 'Your Browser is Obsolete'"
else
  upgrade_test = nil
end

file_from 'test/functional/pages_controller_test.rb', binding

file_from 'test/functional/password_reset_controller_tests.rb', binding

file_from 'test/integration/new_user_can_register_test.rb', binding

file_from 'test/integration/user_can_login_test.rb', binding

file_from 'test/integration/user_can_logout_test.rb', binding

commit_state "basic tests"

# authlogic setup
file_from 'app/controllers/accounts_controller.rb', binding

file_from 'app/controllers/password_resets_controller.rb', binding

file_from 'app/controllers/user_sessions_controller.rb', binding

file_from 'app/controllers/users_controller.rb', binding

file_from 'app/models/notifier.rb', binding

file_from 'app/models/user.rb', binding

file 'app/models/user_session.rb', <<-END
class UserSession < Authlogic::Session::Base
end
END

file_from 'app/views/notifier/password_reset_instructions.html.erb', binding

file_from 'app/views/notifier/welcome_email.html.erb', binding

file_from 'app/views/password_resets/edit.html.erb', binding, "password_resets_edits.html.erb"

file 'app/views/password_resets/new.html.erb', binding, "password_resets_new.html.erb"

if design == "bluetrip"
  file 'app/views/user_sessions/new.html.erb', binding, "bluetrip_user_sessions_new.html.erb"
else
  file 'app/views/user_sessions/new.html.erb', binding, "none_bluetrip_user_sessions_new.html.erb"
end

file_from 'app/views/users/index.html.erb', binding

file_from 'app/views/users/_form.html.erb', binding

if design == "bluetrip" 
  file_from 'app/views/users/edit.html.erb', binding, "blueprint_edit.html.erb"
else
  file_from 'app/views/users/edit.html.erb', binding, "no_blueprint_edit.html.erb"
end

if design == "bluetrip"
  file_from 'app/views/users/new.html.erb', binding, "bluetrip_new.html.erb"
else
  file_from 'app/views/users/new.html.erb', binding, "no_blueprint_new.html.erb"
end

file_from 'app/views/users/show.html.erb', binding

file_from 'db/migrate/01_create_users.rb', binding

file_from 'db/migrate/02_create_sessions.rb', binding

commit_state "basic Authlogic setup"

# static pages
if ie6_blocking == "light"
  ie6_method = <<-END
  def upgrade
    @page_title = "Your Browser is Obsolete"
  end
END
end

file_from 'app/controllers/pages_controller.rb', binding

if ie6_blocking == "light"
  ie6_warning = <<-END
  <!--[if lt IE 7]>
	<p class="flash_error">
		Your browser is obsolete. For best results in #{current_app_name}, please <%= link_to "Upgrade", pages_path(:action => 'upgrade'), :target => :blank %>
	</p>
  <![endif]-->
END
elsif ie6_blocking == "ie6nomore"
  ie6_warning = <<-END
  <!--[if lt IE 7]>
  <div style='border: 1px solid #F7941D; background: #FEEFDA; text-align: center; clear: both; height: 75px; position: relative;'>
    <div style='position: absolute; right: 3px; top: 3px; font-family: courier new; font-weight: bold;'><a href='#' onclick='javascript:this.parentNode.parentNode.style.display="none"; return false;'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-cornerx.jpg' style='border: none;' alt='Close this notice'/></a></div>
    <div style='width: 640px; margin: 0 auto; text-align: left; padding: 0; overflow: hidden; color: black;'>
      <div style='width: 75px; float: left;'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-warning.jpg' alt='Warning!'/></div>
      <div style='width: 275px; float: left; font-family: Arial, sans-serif;'>
        <div style='font-size: 14px; font-weight: bold; margin-top: 12px;'>You are using an outdated browser</div>
        <div style='font-size: 12px; margin-top: 6px; line-height: 12px;'>For a better experience using this site, please upgrade to a modern web browser.</div>
      </div>
      <div style='width: 75px; float: left;'><a href='http://www.firefox.com' target='_blank'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-firefox.jpg' style='border: none;' alt='Get Firefox 3.5'/></a></div>
      <div style='width: 75px; float: left;'><a href='http://www.browserforthebetter.com/download.html' target='_blank'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-ie8.jpg' style='border: none;' alt='Get Internet Explorer 8'/></a></div>
      <div style='width: 73px; float: left;'><a href='http://www.apple.com/safari/download/' target='_blank'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-safari.jpg' style='border: none;' alt='Get Safari 4'/></a></div>
      <div style='float: left;'><a href='http://www.google.com/chrome' target='_blank'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-chrome.jpg' style='border: none;' alt='Get Google Chrome'/></a></div>
    </div>
  </div>
  <![endif]-->
END
end

if design == "bluetrip"
  top_menu_class = "span-24"
  left_menu_class = "span-5 suffix-1"
  main_with_left_menu_class = "span-17 suffix-1 last"
else
  top_menu_class = nil;
  left_menu_class = nil;
  main_with_left_menu_class = nil;
end

file_from 'app/views/pages/home.html.erb', binding

file_from 'app/views/pages/css_test.html.erb', binding

if ie6_blocking == 'light'
file 'app/views/pages/upgrade.html.erb', <<-END
<div id="ie6msg">
<h4>#{current_app_name} works best with a newer browser than you are using.</h4>
<p>To get the best possible experience using #{current_app_name}, we recommend that you upgrade your browser to a newer version. The current version is <a href="http://www.microsoft.com/windows/downloads/ie/getitnow.mspx" target="_blank">Internet Explorer 7</a> or <a href="http://www.microsoft.com/windows/internet-explorer/default.aspx target="_blank"">Internet Explorer 8</a>. The upgrade is free. If you’re using a PC at work you should contact your IT-administrator. Either way, we'd like to encourage you to stop using IE6 and try a more secure and Web Standards-friendly browser.</p>
<p>#{current_app_name} also supports other popular browsers like <strong><a href="http://getfirefox.com" target="_blank">Firefox</a></strong> or <strong><a href="http://www.opera.com" target="_blank">Opera</a></strong>.</p>
</div>
END
end

file_from 'doc/README_FOR_APP', binding

commit_state "static pages"

# simple default routing
file_from 'config/routes.rb', binding

commit_state "routing"

# databases
rake('db:create')
rake('db:migrate')
rake('parallel:prepare[4]')
commit_state "databases set up"

# rakefile for metric_fu
rakefile 'metric_fu.rake', <<-END
require 'metric_fu'
MetricFu::Configuration.run do |config|
  # not doing saikuro at the moment 
  config.metrics  = [:churn, :stats, :flog, :flay, :reek, :roodi, :rcov]
  config.rcov[:rcov_opts] << "-Itest"
  # config.flay     = { :dirs_to_flay => ['app', 'lib']  } 
  # config.flog     = { :dirs_to_flog => ['app', 'lib']  }
  # config.reek     = { :dirs_to_reek => ['app', 'lib']  }
  # config.roodi    = { :dirs_to_roodi => ['app', 'lib'] }
  # config.saikuro  = { :output_directory => 'scratch_directory/saikuro', 
  #                     :input_directory => ['app', 'lib'],
  #                     :cyclo => "",
  #                     :filter_cyclo => "0",
  #                     :warn_cyclo => "5",
  #                     :error_cyclo => "7",
  #                     :formater => "text"} #this needs to be set to "text"
  # config.churn    = { :start_date => "1 year ago", :minimum_churn_count => 10}
  # config.rcov     = { :test_files => ['test/**/*_test.rb', 
  #                                     'spec/**/*_spec.rb'],
  #                     :rcov_opts => ["--sort coverage", 
  #                                    "--no-html", 
  #                                    "--text-coverage",
  #                                    "--no-color",
  #                                    "--profile",
  #                                    "--rails",
  #                                    "--exclude /gems/,/Library/,spec"]}
end
END

commit_state "metric_fu setup"

# vendor rails if desired
# takes the edge of whatever branch is specified in the config file
# defaults to 2-3-stable at the moment
if rails_strategy == "vendored" || rails_strategy == "symlinked"
  if rails_strategy == "vendored"
    install_rails :branch => rails_branch
    commit_state "vendored rails"
  elsif rails_strategy == "symlinked"
    inside('vendor') do
      run("ln -s #{link_rails_root} rails")
    end
  end
  update_app
  commit_state "updated rails files from vendored copy"
end

# set up branches
branches = template_options["git_branches"]
if !branches.nil?
  default_branch = "master"
  branches.each do |name, default|
    if name != "master"
      git :branch => name
      default_branch = name if !default.nil?
    end
  end
  git :checkout => default_branch if default_branch != "master"
  log "set up branches #{branches.keys.join(', ')}"
end

# Success!
puts "SUCCESS!"
if exception_handling == "exceptional"
  puts '  Set up new app at http://getexceptional.com/apps'
  puts '  Put the right API key in config/exceptional.yml'
end
if exception_handling == "hoptoad"
  puts '  Set up new app at https://<your subdomain>.hoptoadapp.com/projects/new'
  puts '  Put the right API key in config/initializers/hoptoad.rb'
end
if monitoring == "new_relic"
  puts '  Put the right API key in config/new_relic.yml'
end
if monitoring == "scout"
  puts '  Put the right plugin ID in config/scout.yml'
  puts '  Install the scout agent gem on the production server (sudo gem install scout_agent)'
end
puts '  Put the production database password in config/database.yml'
puts '  Put mail server information in mail.rb'
puts '  Put real IP address and git repo URL in deployment files'
puts '  Add app to gitosis config'
puts "  git remote add origin git@#{capistrano_repo_host}:#{current_app_name}.git"
puts '  git push origin master:refs/heads/master'
