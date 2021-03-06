include_recipe 'habitat-build::provision'

load_delivery_chef_config

gh_token = data_bag_item('secrets', 'github')['token']
latest = data_bag_item('rust-hello-world', 'latest')['build']
depot_url = node['habitat-build']['depot-url']
stage = node['delivery']['change']['stage']
ident = data_bag_item('rust-hello-world', latest)['artifact']['pkg_ident']

execute 'promote-hab-artifact' do
  command "curl -I -X POST -H \"Authorization: Bearer #{gh_token}\" #{depot_url}/views/#{stage}/pkgs/#{ident}/promote"
end
