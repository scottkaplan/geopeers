#!/usr/bin/ruby

require 'aws-sdk'

def get_production_ami
  
end

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

def run_cloudformation cf_file
  region = 'us-west-2'
  stack_name = File.basename(cf_file, ".*")
  stack_name.gsub!(/_/,'-')
  begin
    cloudformation = Aws::CloudFormation::Client.new(region: region)
    resp = cloudformation.create_stack(
      stack_name: stack_name,
      template_body: File.read(cf_file),
      disable_rollback: true,
    )
    puts resp.stack_id
  rescue Aws::EC2::Errors::ServiceError => e
    return e
  end

end

if ARGV[0]
  err = run_cloudformation (ARGV[0])
  if err
    puts err
  end
else
  puts "Please supply the name of the CF JSON file"
end
# err = launch_ami ("ami-ff14f3bb")
