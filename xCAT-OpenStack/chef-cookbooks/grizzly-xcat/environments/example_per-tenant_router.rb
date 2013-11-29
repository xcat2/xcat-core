# 
# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
# http://docs.openstack.org/grizzly/openstack-network/admin/content/app_demo_routers_with_private_networks.html
#
#

name "example_per-tenant_router"
description "Grizzly environment file based on Per-tenant Routers with Private Networks"

override_attributes(
  "mysql" => {
    "server_root_password" => "cluster",
    "server_debian_password" => "cluster",
    "server_repl_password" => "cluster",
    "allow_remote_root" => true,
    "root_network_acl" => "%"
  },
  "openstack" => {
    "developer_mode" => true,
    "db"=>{
       "bind_interface"=>"eth1", 
        "compute"=>{
           "host"=>"11.1.0.107"
        },
        "identity"=>{
           "host"=>"11.1.0.107"
        },
        "image"=>{
           "host"=>"11.1.0.107"
        },
        "network"=>{
           "host"=>"11.1.0.107"
        },
        "volume"=>{
           "host"=>"11.1.0.107"
        },
        "dashboard"=>{
           "host"=>"11.1.0.107"
        },
        "metering"=>{
           "host"=>"11.1.0.107"
        }
     },
    "mq"=>{
        "bind_interface"=>"eth1"
     },
    "identity"=>{
        "bind_interface"=>"eth1", 
        "db"=>{
            "username"=>"keystone",
            "password"=> "keystone"
         }
     },

    "endpoints"=>{
        "identity-api"=>{
           "host"=>"11.1.0.107",
        },
        "identity-admin"=>{
           "host"=>"11.1.0.107",
        },
        "compute-api"=>{
           "host"=>"11.1.0.107",
        },
        "compute-ec2-api"=>{
           "host"=>"11.1.0.107",
        },
        "compute-ec2-admin"=>{
           "host"=>"11.1.0.107",
        },
        "compute-xvpvnc"=>{
           "host"=>"11.1.0.107",
        },
        "compute-novnc"=>{
           "host"=>"11.1.0.107",
        },
        "network-api"=>{
           "host"=>"11.1.0.107",
        },
        "image-api"=>{
           "host"=>"11.1.0.107",
        },
        "image-registry"=>{
           "host"=>"11.1.0.107",
        },
        "volume-api"=>{
           "host"=>"11.1.0.107",
        },
        "metering-api"=>{
           "host"=>"11.1.0.107",
        }
     },


   "image" => {
    "api"=>{
        "bind_interface"=>"eth1"
     },
    "registry"=>{
        "bind_interface"=>"eth1" 
     },
     "image_upload" => false,
     "upload_images" => ["cirros"],
     "upload_image" => {
       "cirros" => "https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img"
     },
   },
   "dashboard" => {
      "use_ssl" => "false"
   },
   "network" => {
        "metadata"=>{
           "nova_metadata_ip"=>"11.1.0.107"
        },
        "rabbit"=>{
           "host"=>"11.1.0.107"
        },
        "api"=>{
            "bind_interface"=>"eth1"
         },
        "l3"=>{
            "external_network_bridge_interface"=>"eth0" 
         },
        "allow_overlapping_ips" => "True",
        "use_namespaces" => "True",
        "openvswitch"=> {
            "tenant_network_type"=>"gre",
            "tunnel_id_ranges"=>"1:1000",
            "enable_tunneling"=>"True",
            "local_ip_interface"=>"eth2" 
        }
   },
   "compute" => {
        "identity_service_chef_role" => "os-compute-single-controller",
        "rabbit"=>{
           "host"=>"11.1.0.107"
        },
       "xvpvnc_proxy"=>{
           "bind_interface"=>"eth0" 
       },
       "novnc_proxy"=>{
           "bind_interface"=>"eth0" 
       },
       "network" => {
           "service_type" => "quantum",
       },
      "config" => {
           "ram_allocation_ratio" => 5.0
      },
      "libvirt" => { 
           "bind_interface"=>"eth1",  
           "virt_type" => "qemu" 
      }    
   }
  }
  )
