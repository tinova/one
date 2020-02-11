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

    def initialize(service_pool, interval = 30)
        @interval = interval
        @srv_pool = service_pool
    end

    def start
        loop do
            @srv_pool.info

            @srv_pool.each do |service|
                service.info

                Log.info LOG_COMP,
                         'Checking elasticity policies for ' \
                         "service: #{service['/DOCUMENT/ID']}"

                scale(service)
            end

            sleep(@interval)
        end
    end

    private

    def scale(service)
        service.roles.each do |_, role|
            elasticity_policies = role.elasticity_policies

            next if elasticity_policies.empty?

            elasticity_policies.each do |policy|
                case policy['type']
                when 'CHANGE'
                    split_expr = policy['expression']

                    if split_expr.size < 3
                        Log.error LOG_COMP,
                                  "Error in expression #{policy['expression']}"
                    end

                    expr_attr, expr_sign, expr_value = split_expr
                end
require 'pry'
binding.pry
            end
        end
    end

end
# rubocop:enable Naming/FileName
