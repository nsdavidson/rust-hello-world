#
# Cookbook Name:: build-cookbook
# Recipe:: provision
#
# Copyright (c) 2016 The Authors, All Rights Reserved.
include_recipe 'habitat-build::provision'

gh_token = data_bag_item('secrets', 'github')[:token]

gh_token = ''
depot_url = node['habitat']['depot_url']
stage = node['delivery']['change']['stage']

execute 'promote-hab-artifact' do
  command "curl -I -X POST \"Authorization: Bearer #{gh_token}\" http://#{depot_url}/views/#{stage}/pkgs/"
end
