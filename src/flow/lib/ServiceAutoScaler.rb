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

# Service auto scaler class
class ServiceAutoScaler

    LOG_COMP = 'AE'

    def initialize(service_pool, options, interval = 1)
        @conf       = options

        @lcm        = options[:lcm]
        @interval   = interval
        @srv_pool   = service_pool

        @cloud_auth = @conf[:cloud_auth]
        @client     = client
    end

    def start
        loop do
            @srv_pool.info

            @srv_pool.each do |service|
                service.info

                Log.info LOG_COMP,
                         'Checking elasticity policies for ' \
                         "service: #{service['/DOCUMENT/ID']}"

                # TODO skip done

                apply_scaling_policies(service)
            end

            sleep(@interval)
        end
    end

    private

    # Get OpenNebula client
    def client
        # If there's a client defined use it
        return @client unless @client.nil?

        # If not, get one via cloud_auth
        @cloud_auth.client
    end

    # If a role needs to scale, its cardinality is updated, and its state is set
    # to SCALING. Only one role is set to scale.
    # @param  [Service] service
    def apply_scaling_policies(service)
        Log.debug LOG_COMP, 'Apply scaling policies', service.id

        service.roles.each do |name, role|
            diff, cooldown_duration = role.scale?

            if diff != 0
                Log.debug LOG_COMP,
                          "Role #{name} needs to scale #{diff} nodes",
                          service.id

                @lcm.scale_action(client,
                                  service.id,
                                  name,
                                  role.cardinalit + diff,
                                  false)
            end
        end
    end

end
# rubocop:enable Naming/FileName
