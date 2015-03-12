#!/usr/bin/ruby

require 'aws-sdk'

ec2 = Aws::EC2::Client.new(
  region: 'us-west-1',
  access_key_id: 'AKIAJTFJU7ILKPRFXFKA',
  secret_access_key: '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',
)
# puts ec2.operation_names
#ec2.instances.create(:image_id => "ami-ff14f3bb")
#Aws.config(:credential_provider => Aws::Core::CredentialProviders::EC2Provider.new)
resp = ec2.run_instances(image_id: "ami-ff14f3bb",
                         min_count: 1,
                         max_count: 1,
                         instance_type: "t2.micro",
                         key_name: "geopeers",
                         network_interfaces:  [
                           {
                             device_index: 0,
                             subnet_id: "subnet-76f75213",
                             associate_public_ip_address: true,
                           },
                         ],
                         iam_instance_profile: {
                           name: "geopeers_server",
                         },
                        )
