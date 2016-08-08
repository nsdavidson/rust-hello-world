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

execute 'promote-hab-artifact' do
  command "curl -I -X POST \"Authorization: Bearer #{gh_token}\" http://#{depot_url}/views/#{stage}/pkgs/"
end
