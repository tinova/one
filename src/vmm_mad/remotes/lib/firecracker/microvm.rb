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
require 'command' # TODO, use same class LXD

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

        @jailer_command = 'sudo jailer'
        @vnc_command    = 'screen -x'

        if !@one.nil?
            @rootfs_dir = "/srv/jailer/firecracker/one-#{@one.vm_id}/root"
            @context_path = "#{@rootfs_dir}/context"
        end
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

    def gen_deployment_file
        File.open("#{vm_location}/deployment.file", 'w+') do |file|
            file.write(@fc['deployment-file'].to_json)
        end
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
    # VNC
    #---------------------------------------------------------------------------

    # Start the svncterm server if it is down.
    def vnc(signal)
        command = @one.vnc_command(signal, @vnc_command)
        return if command.nil?

        w = @one.fcrc[:vnc][:width]
        h = @one.fcrc[:vnc][:height]
        t = @one.fcrc[:vnc][:timeout]

        vnc_args = "-w #{w} -h #{h} -t #{t}"

        pipe = '/tmp/svncterm_server_pipe'
        bin  = 'svncterm_server'
        server = "#{bin} #{vnc_args}"

        rc, _o, e = Command.execute_once(server, true)

        unless [nil, 0].include?(rc)
            OpenNebula.log_error("#{__method__}: #{e}\nFailed to start vnc")
            return
        end

        lfd = Command.lock

        File.open(pipe, 'a') do |f|
            f.write command
        end
    ensure
        Command.unlock(lfd) if lfd
    end

    #---------------------------------------------------------------------------
    # Container Management & Monitor
    #---------------------------------------------------------------------------

    # Create a microVM
    def create
        # Build jailer command paramas
        cmd = "screen -L -Logfile /tmp/fc-log-#{@one.vm_id} -dmS " \
              "one-#{@one.vm_id} #{@jailer_command}"

        @fc['command-params']['jailer'].each do |key, val|
            cmd << " --#{key} #{val}"
        end

        # Build firecracker params
        cmd << " --"
        @fc['command-params']['firecracker'].each do |key, val|
            cmd << " --#{key} #{val}"
        end

        map_chroot_path

        system(cmd)
    end

    # Poweroff the microVM by sending CtrlAltSupr signal
    def shutdown(wait: true, timeout: '')
        data = '{"action_type": "SendCtrlAltDel"}'
        @client.put("actions", data)

        true
    end

    # Poweroff hard the microVM by killing the process
    def cancel(wait: true, timeout: '')
        pid = `ps auxwww | grep "^.*firecracker.*\-\-id=one-#{@one.vm_id}"`.split[1]

        system("kill -9 #{pid}")
    end

    # Clean resources and directories after shuttingdown the microVM
    def clean
        # remove jailer generated files
        rc = system("sudo rm -rf #{@rootfs_dir}/dev/")
        rc &= system("rm -rf #{@rootfs_dir}/api.socket")
        rc &= system("rm -rf #{@rootfs_dir}/firecracker")

        # unmount vm directory
        rc &= `sudo umount #{@rootfs_dir}`

        # remove chroot directory
        rc &= system("rm -rf #{File.expand_path("..", @rootfs_dir)}") if rc

        rc
    end

end
