#!/usr/bin/ruby

require 'aws-sdk'

def launch_ami(ami_id,
               region: 'us-west-1',
               instance_type: 't2.micro',
               vpc_name: 'vpc-geopeers'
              )


  begin
    ec2 = Aws::EC2::Client.new(
      region: region,
    )

    # look for one available VPC named vpc_name
    resp = ec2.describe_vpcs(
      filters: [
        {
          name: "state",
          values: ["available"],
        },
        {
          name: "tag-value",
          values: [vpc_name],
        },
      ],
    )
    vpc_id = resp.vpcs[0].vpc_id
    return "No VPC" unless vpc_id

    # Look for the subnets in this VPC
    resp = ec2.describe_subnets(
      filters: [
        {
          name: "state",
          values: ["available"],
        },
        {
          name: "vpc-id",
          values: [vpc_id],
        },
      ],
    )
    return "No subnets in #{vpc_id}" unless resp.subnets.length > 0
    return "Multiple subnets in #{vpc_id}" unless resp.subnets.length == 1
    subnet_id = resp.subnets[0].subnet_id
    puts subnet_id
    return
    
    resp = ec2.run_instances(
      image_id: ami_id,
      min_count: 1,
      max_count: 1,
      instance_type: instance_type,
      key_name: "geopeers",
      network_interfaces:  [
        {
          device_index: 0,
          subnet_id: subnet_id,
          associate_public_ip_address: true,
        },
      ],
      iam_instance_profile: {
        name: "geopeers_server",
      },
    )
  rescue Aws::EC2::Errors::ServiceError => e
    return e
  end
end

err = launch_ami ("ami-ff14f3bb")
if err
  puts err
end
