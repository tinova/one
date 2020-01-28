# rubocop:disable Naming/FileName
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

require 'ffi-rzmq'
require 'EventManager'

# Service watchdog class
class ServiceWD

    # --------------------------------------------------------------------------
    # Default configuration options for the module
    # --------------------------------------------------------------------------
    DEFAULT_CONF = {
        :subscriber_endpoint  => 'tcp://localhost:2101',
        :timeout_s   => 30,
        :concurrency => 10,
        :cloud_auth  => nil
    }

    ############################################################################
    # WARNING STATES
    ############################################################################
    WARNING_STATES = %w[
        POWEROFF
        UNKNOWN
    ] + EventManager::FAILURE_STATES

    # Class constructor
    #
    # @param options [Hash] event manager options
    def initialize(client, options)
        @conf = DEFAULT_CONF.merge(options)

        @lcm        = options[:lcm]
        @context    = ZMQ::Context.new(1)
        @cloud_auth = @conf[:cloud_auth]
        @client     = client

        @services_nodes = {}
    end

    def start_watching(service_id, roles)
        @services_nodes[service_id] = {}

        roles.each do |name, role|
            @services_nodes[service_id][name] = {}
            @services_nodes[service_id][name] = role.nodes_ids
        end

        # check that all nodes are in RUNNING state, if not, notify
        check_roles_health(client, service_id, roles)

        # subscribe to all nodes
        subscriber = gen_subscriber

        @services_nodes[service_id].each do |_, nodes|
            nodes.each do |node|
                subscribe(node, subscriber)
            end
        end

        key     = ''
        content = ''

        # wait until there are no nodes
        until @services_nodes[service_id].empty?
            rc = subscriber.recv_string(key)
            rc = subscriber.recv_string(content) if rc != -1

            if rc == -1 && ZMQ::Util.errno != ZMQ::EAGAIN
                Log.error LOG_COMP, 'Error reading from subscriber.'
            end

            next if key.nil?

            next if key.split[2].nil?

            node      = key.split[2].split('/')[0].to_i
            state     = key.split[2].split('/')[1]
            lcm_state = key.split[2].split('/')[2]
            role_name = find_by_id(service_id, node)

            # if the VM is not from the service skip
            next if role_name.nil?

            states = {}
            states[:state] = state
            states[:lcm]   = lcm_state

            check_role_health(client, service_id, role_name, node, states)
        end
    end

    def stop_watching(service_id)
        # unsubscribe from all nodes
        subscriber = gen_subscriber

        @services_nodes[service_id].each do |_, nodes|
            nodes.each do |node|
                unsubscribe(node, subscriber)
            end
        end

        # reset the service nodes object
        @services_nodes[service_id] = {}
    end

    def update_node(service_id, role_name, node)
        subscriber = gen_subscriber

        unsubscribe(node, subscriber)

        @service_nodes[service_id][role_name].delete(node)

        if @service_nodes[service_id][role_name].empty?
            @service_nodes[service_id].delete(role_name)
        end
    end

    private

    def client
        # If there's a client defined use it
        return @client unless @client.nil?

        # If not, get one via cloud_auth
        @cloud_auth.client
    end

    def gen_subscriber
        subscriber = @context.socket(ZMQ::SUB)

        # Set timeout (TODO add option for customize timeout)
        subscriber.setsockopt(ZMQ::RCVTIMEO, @conf[:timeout_s] * 10**3)
        subscriber.connect(@conf[:subscriber_endpoint])

        subscriber
    end

    def subscribe(vm_id, subscriber)
        subscriber.setsockopt(ZMQ::SUBSCRIBE, "EVENT VM #{vm_id}")
    end

    def unsubscribe(vm_id, subscriber)
        subscriber.setsockopt(ZMQ::UNSUBSCRIBE, "EVENT VM #{vm_id}")
    end

    def check_roles_health(client, service_id, roles)
        roles.each do |name, role|
            role.nodes_ids.each do |node|
                check_role_health(client, service_id, name, node)
            end
        end
    end

    ############################################################################
    # HELPERS
    ############################################################################

    def find_by_id(service_id, node)
        ret = @services_nodes[service_id].find do |_, nodes|
            nodes.include?(node)
        end

        ret[0] unless ret.nil?
    end

    def check_role_health(client, service_id, role_name, node, states = nil)
        if states.nil?
            vm = OpenNebula::VirtualMachine.new_with_id(node, client)
            vm.info

            vm_state     = OpenNebula::VirtualMachine::VM_STATE[vm.state]
            vm_lcm_state = OpenNebula::VirtualMachine::LCM_STATE[vm.lcm_state]
        else
            vm_state     = states[:state]
            vm_lcm_state = states[:lcm]
        end

        if WARNING_STATES.include?(vm_lcm_state) ||
           WARNING_STATES.include?(vm_state)
            action = :error_wd_cb
        elsif vm_state == 'DONE'
            action = :done_wd_cb
        elsif vm_lcm_state == 'RUNNING'
            action = :running_wd_cb
        else
            return
        end

        @lcm.trigger_action(action,
                            service_id,
                            client,
                            service_id,
                            role_name,
                            node)
    end

end

# rubocop:enable Naming/FileName
