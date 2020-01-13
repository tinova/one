#!/usr/bin/ruby

# -------------------------------------------------------------------------- #
# Copyright 2002-2019, OpenNebula Project, OpenNebula Systems                #
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

$LOAD_PATH.unshift File.dirname(__FILE__)

require 'client'
require 'opennebula_vm'

# This class interacts with Firecracker
class MicroVM

    #---------------------------------------------------------------------------
    # Class constructors & static methods
    #---------------------------------------------------------------------------
    # Creates the microVM object in memory.
    # Can be later created in Firecracker using create method
    def initialize(fc, one, client)
        @client = client

        @fc = fc
        @one = one

        #@lxc_command = 'lxc'
        #@lxc_command.prepend 'sudo ' if client.snap

        @rootfs_dir = "/srv/jailer/firecracker/one-#{@one.vm_id}/root"
        @context_path = "#{@rootfs_dir}/context"
    end

    class << self

        # Returns specific container, by its name
        # Params:
        # +name+:: container name
        def get(name, one_xml, client)
            info = client.get("#{CONTAINERS}/#{name}")['metadata']

            one  = nil
            one  = OpenNebulaVM.new(one_xml) if one_xml

            Container.new(info, one, client)
        end

        # Creates container from a OpenNebula VM xml description
        def new_from_xml(one_xml, client)
            one = OpenNebulaVM.new(one_xml)

            MicroVM.new(one.to_fc, one, client)
        end

        # Returns an array of container objects
        def get_all(client)
            containers = []

            container_names = client.get(CONTAINERS)['metadata']
            container_names.each do |name|
                name = name.split('/').last
                containers.push(get(name, nil, client))
            end

            containers
        end

        # Returns boolean indicating the container exists(true) or not (false)
        def exist?(name, client)
            client.get("#{CONTAINERS}/#{name}")
            true
        rescue LXDError => e
            raise e if e.code != 404

            false
        end

    end

    #---------------------------------------------------------------------------
    # Utils
    #---------------------------------------------------------------------------

    def deployment_file
        @fc['deployment-file'].to_json
    end

    def vm_location
        "#{@one.sysds_path}/#{@one.vm_id}"
    end

    def map_chroot_path
        `mkdir -p #{@rootfs_dir}`

        # TODO, add option for hard links
        `sudo mount -o bind #{@one.sysds_path}/#{@one.vm_id} #{@rootfs_dir}`
    end

    #---------------------------------------------------------------------------
    # Container Management & Monitor
    #---------------------------------------------------------------------------

    # Create a microVM
    def create(wait: true, timeout: '')
        # Build jailer command paramas
        cmd = "screen -L -Logfile /tmp/fc-log-#{@one.vm_id} -dmS microvm-#{@one.vm_id} sudo jailer"

        @fc['command-params']['jailer'].each do |key, val|
            cmd << " --#{key} #{val}"
        end

        # Build firecracker params
        cmd << " --"
        @fc['command-params']['firecracker'].each do |key, val|
            cmd << " --#{key} #{val}"
        end

        map_chroot_path

        `#{cmd}`
    end

end
