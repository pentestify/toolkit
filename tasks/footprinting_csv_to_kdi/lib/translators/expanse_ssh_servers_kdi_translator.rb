#encoding: utf-8

require_relative "../mapping"
require_relative "../helpers"

require 'json'
require 'csv'

include Kenna::Helpers
include Kenna::Mapping::External

$assets = []
$vuln_defs = []

SCAN_SOURCE="Expanse"

def create_asset(ip_address, hostname=nil)

  # if we already have it, skip
  return unless $assets.select{|a| a[:ip_address] == ip_address }.empty?

  asset = {
    ip_address: ip_address,
    tags: [],
    priority: 10,
    vulns: []
  }

  # if we have a hostname, add it
  asset[:hostname] = hostname if hostname

  $assets << asset
end

def create_asset_vuln(ip_address, port, vuln_id, first_seen, last_seen)

  # grab the asset
  asset = $assets.select{|a| a[:ip_address] == ip_address}.first

  asset[:vulns] << {
    scanner_identifier: "#{vuln_id}",
    scanner_type: SCAN_SOURCE,
    created_at: first_seen,
    port: port.to_i,
    last_seen_at: last_seen,
    status: "open"
  }

end

# verify we have a valid file
#headers = verify_file_headers(ARGV[0])
headers = [] 

# iterate through the findings, looking for CVEs
CSV.parse(read_input_file("#{ARGV[0]}"), encoding: "UTF-8", row_sep: :auto, col_sep: ",").each_with_index do |row,index|
  # skip first
  if index == 0
    headers = row.to_a
    next 
  end

  # create the asset
  hostname = get_value_by_header(row, headers,"firstObservation.hostname").gsub("*.","")
  ip_address = get_value_by_header(row, headers,"ip")
  port = get_value_by_header(row, headers,"port")
  create_asset ip_address, hostname

  first = get_value_by_header(row, headers,"firstObservation.scanned")
  last = get_value_by_header(row, headers,"lastObservation.scanned")
  if first
    first_seen = Date.strptime("#{first}", "%Y-%m-%d")
  else
    first_seen = Date.today
  end

  if last
    last_seen = Date.strptime("#{last}", "%Y-%m-%d")
  else
    last_seen = Date.today
  end

  server_version = get_value_by_header(row, headers, "firstObservation.configuration.serverVersion")
  version = get_value_by_header(row, headers, "firstObservation.configuration.version")
  extra_info = get_value_by_header(row, headers, "firstObservation.configuration.extraInfo")

  finding_id = unique_finding_string("#{server_version} #{version} #{extra_info}")
  vuln_id = "detected_server_ssh_#{finding_id}"
  description = "SSH Server detected:\n"
  description << "SSH Version: #{version}\n"
  description << "SSH Server Version: #{server_version}\n"
  description << "SSH Extra Info: #{extra_info}\n"

  recommendation = "No action required if this server is intended to be exposed."

  mapped_vuln = get_canonical_vuln_details(SCAN_SOURCE, "#{vuln_id}", description, recommendation)

  create_asset_vuln ip_address, port, vuln_id, first_seen, last_seen
  create_vuln_def mapped_vuln[:name], vuln_id, mapped_vuln[:description], mapped_vuln[:recommendation], mapped_vuln[:cwe]

end

kdi_output = generate_kdi_file
puts JSON.pretty_generate kdi_output