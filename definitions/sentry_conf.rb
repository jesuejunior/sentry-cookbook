# -*- coding: utf-8 -*-
#
# Cookbook Name:: sentry cookbook
# Definition:: sentry_conf
#
# Making sentry configuration file
#
# :copyright: (c) 2012 - 2013 by Alexandr Lispython (alex@obout.ru).
# :license: BSD, see LICENSE for more details.
# :github: http://github.com/Lispython/sentry-cookbook
#

class Chef::Recipe
  include Chef::Mixin::DeepMerge
end

define :sentry_conf, :name => nil, :template => "sentry.conf.erb",
:virtualenv_dir => nil,
:user => "sentry", :group => "group",
:config => nil,
:superusers => [],
:variables => {},
:settings => {} do

  Chef::Log.info("Making sentry config for: #{params[:name]}")
  include_recipe "sentry::default"

  virtualenv_dir = params[:virtualenv_dir] or node["sentry"]["virtulenv"]

  #settings_variables = Chef::Mixin::DeepMerge.deep_merge!(node[:sentry][:settings], params[:settings].to_hash)

  settings_variables = params[:settings]
  config = params[:config] || node["sentry"]["config"]
  settings_variables["config"] = config

  # Making application virtualenv directory
  directory virtualenv_dir do
    owner params[:user]
    group params[:group]
    mode 0777
    recursive true
    action :create
  end

  # Creating virtualenv structure
  python_virtualenv virtualenv_dir do
    owner params[:user]
    group params[:group]
    action :create
  end

  # Creating sentry config
  template config do
    owner params[:user]
    group params[:group]
    source params[:template]
    mode 0777
    variables(settings_variables.to_hash)
  end

  # Intstall sentry via pip
  python_pip "sentry" do
    provider Chef::Provider::PythonPip
    user params[:user]
    group params[:group]
    virtualenv virtualenv_dir
    version node["sentry"]["version"]
    action :install
  end

  # # Install third party plugins
  node["sentry"]["settings"]["third_party_plugins"].each do |item|
    python_pip item["pypi_name"] do
      user params[:user]
      group params[:group]
      provider Chef::Provider::PythonPip
      virtualenv virtualenv_dir
      if item.has_key?("version")
        version item["version"]
      end
      action :install
    end
  end

  bash "chown virtualenv" do
    code <<-EOH
  chown -R #{params['user']}:#{params['group']} #{virtualenv_dir}
  EOH
  end

  # # Run migrations
  # # sentry --config=/etc/sentry.conf.py upgrade
  bash "upgrade sentry" do
    user params[:user]
    group params[:group]
    code <<-EOH
  . #{virtualenv_dir}/bin/activate &&
  #{virtualenv_dir}/bin/python #{virtualenv_dir}/bin/sentry --config=#{config} upgrade --noinput &&
  deactivate
  EOH
  end

  # # Create superusers
  template node["sentry"]["superuser_creator_script"] do
    owner params[:user]
    group params[:group]
    source "superuser_creator.py.erb"
    variables(:config => config,
              :superusers => params[:superusers],
              :virtualenv => virtualenv_dir)
  end

  # # sentry --config=/etc/sentry.conf.py createsuperuser
  bash "create sentry superusers" do
    user params[:user]
    group params[:group]

    code <<-EOH
  . #{virtualenv_dir}/bin/activate &&
  #{virtualenv_dir}/bin/python #{node['sentry']['superuser_creator_script']} &&
  deactivate
  EOH
  end

  file node['sentry']['superuser_creator_script'] do
    action :delete
  end

end