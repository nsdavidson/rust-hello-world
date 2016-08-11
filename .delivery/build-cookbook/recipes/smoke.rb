require 'net/http'

ports = {
    'acceptance' => '8080',
    'union' => '8081',
    'rehearsal' => '8082',
    'delivered' => '8083'
}

stage = node['delivery']['change']['stage']
stage_port = ports[stage]
host = node['build-cookbook']['rust-hello-world']['host']

ruby_block 'smoke-test' do
  block do
    uri = URI("http://#{host}:#{stage_port}/smoke")
    res = Net::HTTP.get_response(uri)

    raise 'Response was not a 200' unless res.code == '200'

    raise 'Response did not contain the proper content' unless res.body.include?('have seen you') && res.body.include?('smoke')
  end
end

