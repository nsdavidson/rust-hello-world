#
# Cookbook Name:: build-cookbook
# Recipe:: default
#
# Copyright (c) 2016 The Authors, All Rights Reserved.

include_recipe 'habitat-build::default'
include_recipe 'rustlang'

execute 'install-clippy' do
  command 'cargo install clippy'
  ignore_failure true
end