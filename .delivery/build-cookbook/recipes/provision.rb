#
# Cookbook Name:: build-cookbook
# Recipe:: provision
#
# Copyright (c) 2016 The Authors, All Rights Reserved.
include_recipe 'habitat-build::provision'

load_delivery_chef_config

gh_token = data_bag_item('secrets', 'github')[:token]

depot_url = node['habitat-build']['depot-url']
stage = node['delivery']['change']['stage']
ident = data_bag_item('rust-hello-world', node['applications']['rust-hello-world'])

execute 'promote-hab-artifact' do
  command "curl -I -X POST -H \"Authorization: Bearer #{gh_token}\" #{depot_url}/views/#{stage}/pkgs/#{}"
end
