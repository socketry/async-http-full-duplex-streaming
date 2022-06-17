#!/usr/bin/env ruby

require "async"
require "async/http/endpoint"
require "async/io/shared_endpoint"
require "async/http/client"
require "async/http/server"

require 'localhost'

# To install dependencies:
# bundle install

# To perform HTTP/1 request without TLS:
# bundle exec ./full-duplex.rb

# To perform HTTP/2 request with TLS:
# bundle exec ./full-duplex.rb https://localhost:9000

# This will generate a temporary self-signed TLS certificate in `~/.localhost`.

def run_server(endpoint)
	bound_endpoint = Async::IO::SharedEndpoint.bound(endpoint)
	
	server = Async::HTTP::Server.for(bound_endpoint, protocol: endpoint.protocol, scheme: endpoint.scheme) do |request|
		Console.logger.info(server, "Incoming request...", version: request.version, headers: request.headers.to_h)
		
		body = Async::HTTP::Body::Writable.new
		
		Async do
			# Read the entire request body asynchronously.
			Console.logger.info(server, "Finished reading body...", body: request.body.join)
			
			# Allow the underlying connection to complete successfully.
			body.write("Upload data received.")
			body.close
		end
		
		Console.logger.info(server, "Sending response...")
		Protocol::HTTP::Response[200, [["hello", "client"]], body]
	end
	
	Async do
		server.run
	end
end

def run_client(endpoint)
	client = Async::HTTP::Client.new(endpoint)
	
	body = Async::HTTP::Body::Writable.new
	
	body_writer = Async do |task|
		Console.logger.info(client, "Starting writing body...")
		# Take about 1 second to write the entire body:
		10.times do
			Console.logger.info(client, "Writing chunk...")
			body.write("!")
			task.sleep(0.1)
		end
	ensure
		Console.logger.info(client, "Finished writing body...")
		body.close
	end
	
	Console.logger.info(client, "Sending request...")
	response = client.post("/", [["hello", "server"]], body)
	Console.logger.info(client, "Got response...", headers: response.headers.to_h)
	Console.logger.info(client, "Got reponse...", body: response.body.join)
end

endpoint = Async::HTTP::Endpoint.parse(ARGV.pop || "http://localhost:9000")

Sync do
	if endpoint.secure?
		# Generate self-signed key pair and set up alpn:
		authority = Localhost::Authority.fetch(endpoint.hostname)
		server_context = authority.server_context
		server_context.alpn_select_cb = lambda do |protocols|
			protocols.last
		end
		
		client_context = authority.client_context
		client_context.alpn_protocols = ["http/1.1", "h2"]
		
		server_endpoint = endpoint.with(ssl_context: server_context)
		client_endpoint = endpoint.with(ssl_context: client_context)
	else
		server_endpoint = client_endpoint = endpoint
	end
	
	server_task = run_server(server_endpoint)
	run_client(client_endpoint)
ensure
	server_task&.stop
end
