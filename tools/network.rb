#!/usr/bin/ruby

require 'aws-sdk'

RegionParms = {
  "us-east-1" => {
    CidrBlock: "10.1.0.0/16",
    AZs: [ "us-east-1a", "us-east-1c" ],
    NatKeyName: "geopeers",
    NatInstanceType: "t2.micro",
    NatAmiId: "ami-4c9e4b24",
    BastionKeyName: "geopeers",
    BastionInstanceType: "t2.micro",
    BastionAmiId: "ami-b66ed3de",
  },
  "us-west-1" => {
    CidrBlock: "10.2.0.0/16",
    AZs: [ "us-west-1a" ],
    AZ: "us-west-1a",
    NatKeyName: "geopeers",
    NatInstanceType: "t2.micro",
    NatAmiId: "ami-4c9e4b24",
    BastionKeyName: "geopeers",
    BastionInstanceType: "t2.micro",
    BastionAmiId: "ami-b66ed3de",
  },
  "us-west-2" => {
    CidrBlock: "10.3.0.0/16",
    AZs: [ "us-west-2a" ],
    AZ: "us-west-2a",
    NatKeyName: "geopeers",
    NatInstanceType: "t2.micro",
    NatAmiId: "ami-4c9e4b24",
  },
}

AZParms = {
  "us-east-1a" => {
    PublicCidrBlock: "10.1.1.0/24",
    PrivateCidrBlock: "10.1.11.0/24"
  },
  "us-east-1c" => {
    PublicCidrBlock: "10.1.2.0/24",
    PrivateCidrBlock: "10.1.12.0/24"
  },
  "us-west-1a" => {
    PublicCidrBlock: "10.2.1.0/24",
    PrivateCidrBlock: "10.2.11.0/24"
  },
  "us-west-1a" => {
    PublicCidrBlock: "10.3.1.0/24",
    PrivateCidrBlock: "10.3.11.0/24"
  },
}

REGION = 'us-west-2'
STACK_NAME = 'geopeers2'
cidr_block = RegionParms[REGION][:CiderBlock]
az = RegionParms[REGION][:AZ]

network_config = {
  AWSTemplateFormatVersion: "2010-09-09",
  Description: "Build VPC w/INET GW, public & private subnets, bastion host and NAT",
  Parameters: {},

  Resources: {
    VPC: {
      Type: "AWS::EC2::VPC",
      Properties: {
	CidrBlock: cidr_block,
	Tags: [
	  {
            Key: "Application",
            Value: STACK_NAME,
          },
	  {
            Key: "Network",
            Value: "Public",
          },
	],
      },
    },	# VPC
    
    InternetGateway: {
      Type: "AWS::EC2::InternetGateway",
      Properties: {
	Tags: [
	  {
            Key: "Application",
            Value: STACK_NAME,
          },
	  {
            Key: "Network",
            Value: "Public",
          },
	],
      },
    },

    AttachGateway: {
      Type: "AWS::EC2::VPCGatewayAttachment",
      Properties: {
	VpcId: '{ "Ref" : "VPC" }',
	InternetGatewayId: '{ "Ref" : "InternetGateway" }'
      }
    },

    PublicRouteTable: {
      Type: "AWS::EC2::RouteTable",
      Properties: {
	VpcId: '{"Ref" : "VPC"}',
	Tags: [
	  {
            Key: "Application",
            Value: STACK_NAME,
          },
	  {
            Key: "Network",
            Value: "Public",
          },
	],
      },
    },
    
    PublicRoute: {
      Type: "AWS::EC2::Route",
      Properties: {
	RouteTableId: '{ "Ref" : "PublicRouteTable" }',
	DestinationCidrBlock: "0.0.0.0/0",
	GatewayId: '{ "Ref" : "InternetGateway" }',
      }
    },

    PublicSubnet: {
      Type: "AWS::EC2::Subnet",
      Properties: {
	VpcId: '{ "Ref" : "VPC" }',
	AvailabilityZone: az,
	CidrBlock: cidr_block,
      },
      Tags: [
	{
          Key: "Application",
          Value: STACK_NAME,
        },
	{
          Key: "Network",
          Value: "Public",
        },
      ],
    },

    PublicSubnetRouteTableAssociation: {
      Type: "AWS::EC2::SubnetRouteTableAssociation",
      Properties: {
	SubnetId: '{ "Ref" : "PublicSubnet" }',
	RouteTableId: '{ "Ref" : "PublicRouteTable" }',
      },
    },

    
    
  },
}

def build_network
  cf_file = 'cloudformation/geopeers_network.json'
  
  begin
    cloudformation = Aws::CloudFormation::Client.new(region: REGION)
    resp = cloudformation.create_stack(
      stack_name: STACK_NAME,
      template_body: File.read(cf_file),
    )
    puts resp.stack_id
  rescue Aws::EC2::Errors::ServiceError => e
    return e
  end
    
end

err = build_network
puts err if err

