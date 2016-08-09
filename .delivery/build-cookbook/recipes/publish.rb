#
# Cookbook Name:: build-cookbook
# Recipe:: publish
#
# Copyright (c) 2016 The Authors, All Rights Reserved.
include_recipe 'habitat-build::publish'

build_version = nil

ruby_block 'save-build-version' do
  block do
    last_build_env = Hash[*::File.read(::File.join(hab_studio_path,
                                                   'src/results/last_build.env')).split(/[=\n]/)]

    build_version = [last_build_env['pkg_version'], last_build_env['pkg_release']].join('-')
  end
end

node.override['rust-hello-world']['build-version'] = build_version