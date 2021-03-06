# -------------------------------------------------------------------------- #
# Copyright 2002-2020, OpenNebula Project, OpenNebula Systems                #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

ONE_LOCATION = ENV['ONE_LOCATION'] unless defined?(ONE_LOCATION)

if !ONE_LOCATION
    RUBY_LIB_LOCATION = '/usr/lib/one/ruby' unless defined?(RUBY_LIB_LOCATION)
    GEMS_LOCATION     = '/usr/share/one/gems' unless defined?(GEMS_LOCATION)
else
    RUBY_LIB_LOCATION = ONE_LOCATION + '/lib/ruby' \
        unless defined?(RUBY_LIB_LOCATION)
    GEMS_LOCATION     = ONE_LOCATION + '/share/gems' \
        unless defined?(GEMS_LOCATION)
end

if File.directory?(GEMS_LOCATION)
    Gem.use_paths(GEMS_LOCATION)
    $LOAD_PATH.reject! {|l| l =~ /(vendor|site)_ruby/ }
end

$LOAD_PATH << RUBY_LIB_LOCATION

require 'vcenter_driver'
require 'nsx_driver'

# Gather NSX cluster monitor info
class NsxMonitor

    attr_accessor :nsx_status

    def initialize(host_id)
        @host_id = host_id
        @nsx_client = nil
        @nsx_status = ''
        return unless nsx_ready?

        @nsx_client = NSXDriver::NSXClient.new_from_id(host_id)
    end

    def monitor
        # NSX info
        str_info = ''
        str_info << nsx_info
        str_info << tz_info
    end

    def nsx_info
        nsx_info = ''
        nsx_obj = {}
        # In the future add more than one nsx manager
        extension_list = @vi_client.vim.serviceContent
                                   .extensionManager.extensionList
        extension_list.each do |ext_list|
            if ext_list.key == NSXDriver::NSXConstants::NSXV_EXTENSION_LIST
                nsx_obj['type'] = NSXDriver::NSXConstants::NSXV
                url_full = ext_list.client[0].url
                url_split = url_full.split('/')
                # protocol = "https://"
                protocol = url_split[0] + '//'
                # ip_port = ip:port
                ip_port = url_split[2]
                nsx_obj['url'] = protocol + ip_port
                nsx_obj['version'] = ext_list.version
                nsx_obj['label'] = ext_list.description.label
            elsif ext_list.key == NSXDriver::NSXConstants::NSXT_EXTENSION_LIST
                nsx_obj['type'] = NSXDriver::NSXConstants::NSXT
                nsx_obj['url'] = ext_list.server[0].url
                nsx_obj['version'] = ext_list.version
                nsx_obj['label'] = ext_list.description.label
            else
                next
            end
        end
        unless nsx_obj.empty?
            nsx_info << "NSX_MANAGER=\"#{nsx_obj['url']}\"\n"
            nsx_info << "NSX_TYPE=\"#{nsx_obj['type']}\"\n"
            nsx_info << "NSX_VERSION=\"#{nsx_obj['version']}\"\n"
            nsx_info << "NSX_LABEL=\"#{nsx_obj['label']}\"\n"
        end
        nsx_info
    end

    def tz_info
        tz_info = 'NSX_TRANSPORT_ZONES = ['
        tz_object = NSXDriver::TransportZone.new_child(@nsx_client)

        # NSX request to get Transport Zones
        if @one_item['TEMPLATE/NSX_TYPE'] == NSXDriver::NSXConstants::NSXV
            tzs = tz_object.tzs
            tzs.each do |tz|
                tz_info << tz.xpath('name').text << '="'
                tz_info << tz.xpath('objectId').text << '",'
            end
            tz_info.chomp!(',')
        elsif @one_item['TEMPLATE/NSX_TYPE'] == NSXDriver::NSXConstants::NSXT
            r = tz_object.tzs
            r['results'].each do |tz|
                tz_info << tz['display_name'] << '="'
                tz_info << tz['id'] << '",'
            end
            tz_info.chomp!(',')
        else
            raise "Unknown PortGroup type #{@one_item['TEMPLATE/NSX_TYPE']}"
        end
        tz_info << ']'
    end

    def nsx_ready?
        @one_item = VCenterDriver::VIHelper
                    .one_item(OpenNebula::Host, @host_id.to_i)

        # Check if NSX_MANAGER is into the host template
        if [nil, ''].include?(@one_item['TEMPLATE/NSX_MANAGER'])
            @nsx_status = "NSX_STATUS = \"Missing NSX_MANAGER\"\n"
            return false
        end

        # Check if NSX_USER is into the host template
        if [nil, ''].include?(@one_item['TEMPLATE/NSX_USER'])
            @nsx_status = "NSX_STATUS = \"Missing NSX_USER\"\n"
            return false
        end

        # Check if NSX_PASSWORD is into the host template
        if [nil, ''].include?(@one_item['TEMPLATE/NSX_PASSWORD'])
            @nsx_status = "NSX_STATUS = \"Missing NSX_PASSWORD\"\n"
            return false
        end

        # Check if NSX_TYPE is into the host template
        if [nil, ''].include?(@one_item['TEMPLATE/NSX_TYPE'])
            @nsx_status = "NSX_STATUS = \"Missing NSX_TYPE\"\n"
            return false
        end

        # Try a connection as part of NSX_STATUS
        nsx_client = NSXDriver::NSXClient
                     .new_from_id(@vi_client.instance_variable_get(:@host_id)
                     .to_i)

        if @one_item['TEMPLATE/NSX_TYPE'] == NSXDriver::NSXConstants::NSXV
            # URL to test a connection
            url = '/api/2.0/vdn/scopes'
            begin
                if nsx_client.get(url)
                    @nsx_status = "NSX_STATUS = OK\n"
                    true
                else
                    @nsx_status = "NSX_STATUS = \"Response code incorrect\"\n"
                    false
                end
            rescue StandardError => e
                @nsx_status = 'NSX_STATUS = "Error connecting to ' \
                                "NSX_MANAGER: #{e.message}\"\n"
                false
            end
        elsif @one_item['TEMPLATE/NSX_TYPE'] == NSXDriver::NSXConstants::NSXT
            # URL to test a connection
            url = '/api/v1/transport-zones'
            begin
                if nsx_client.get(url)
                    @nsx_status = "NSX_STATUS = OK\n"
                    true
                else
                    @nsx_status = "NSX_STATUS = \"Response code incorrect\"\n"
                    false
                end
            rescue StandardError => e
                @nsx_status = 'NSX_STATUS = "Error connecting to '\
                                "NSX_MANAGER: #{e.message}\"\n"
                false
            end
        end
    end

end
