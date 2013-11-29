#
# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
#

name "example_allinone"
description "Grizzly allinone environment file."

override_attributes(
  "mysql" => {
    "server_root_password" => "cluster",
    "server_debian_password" => "cluster",
    "server_repl_password" => "cluster",
    "allow_remote_root" => true,
    "root_network_acl" => "%"
  },
  "openstack" => {
    "developer_mode" => false,
    "secret"=>{
        "key_path"=>"/etc/chef/encrypted_data_bag_secret"
    },
    "db"=>{
       "bind_interface"=>"lo", 
        "compute"=>{
           "host"=>"127.0.0.1"
        },
        "identity"=>{
           "host"=>"127.0.0.1"
        },
        "image"=>{
           "host"=>"127.0.0.1"
        },
        "network"=>{
           "host"=>"127.0.0.1"
        },
        "volume"=>{
           "host"=>"127.0.0.1"
        },
        "dashboard"=>{
           "host"=>"127.0.0.1"
        },
        "metering"=>{
           "host"=>"127.0.0.1"
        }
     },

    "mq"=>{
        "bind_interface"=>"lo"
     },
    "identity"=>{
        "bind_interface"=>"lo", 
        "db"=>{
            "username"=>"keystone",
            "password"=> "keystone"
         }
     },

    "endpoints"=>{
        "identity-api"=>{
           "host"=>"127.0.0.1",
        },
        "identity-admin"=>{
           "host"=>"127.0.0.1",
        },
        "compute-api"=>{
           "host"=>"127.0.0.1",
        },
        "compute-ec2-api"=>{
           "host"=>"127.0.0.1",
        },
        "compute-ec2-admin"=>{
           "host"=>"127.0.0.1",
        },
        "compute-xvpvnc"=>{
           "host"=>"127.0.0.1",
        },
        "compute-novnc"=>{
           "host"=>"127.0.0.1",
        },
        "network-api"=>{
           "host"=>"127.0.0.1",
        },
        "image-api"=>{
           "host"=>"127.0.0.1",
        },
        "image-registry"=>{
           "host"=>"127.0.0.1",
        },
        "volume-api"=>{
           "host"=>"127.0.0.1",
        },
        "metering-api"=>{
           "host"=>"127.0.0.1",
        }
     },

   "image" => {
       "api"=>{
          "bind_interface"=>"lo"
       },
       "registry"=>{
          "bind_interface"=>"lo" 
       },
       "image_upload" => false,
       "upload_images" => ["cirros"],
       "upload_image" => {
          "cirros" => "https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img"
      },
     "identity_service_chef_role" => "allinone-compute"
   },
   "block-storage" => {
     "keystone_service_chef_role" => "allinone-compute"
   },
   "dashboard" => {
     "keystone_service_chef_role" => "allinone-compute",
      "use_ssl" => "false"
   },
   "network" => {
        "metadata"=>{
           "nova_metadata_ip"=>"127.0.0.1"
        },
        "rabbit"=>{
           "host"=>"127.0.0.1"
        },
        "api"=>{
            "bind_interface"=>"lo"
         },

       "rabbit_server_chef_role" => "allinone-compute",
       "l3"=>{
           "external_network_bridge_interface"=>"eth0"
        },
        "openvswitch"=> {
            "tenant_network_type"=>"vlan",
            "network_vlan_ranges"=>"physnet1",
            "bridge_mappings"=>"physnet1:eth2"
        }
    },
   "compute" => {
       "identity_service_chef_role" => "allinone-compute",
       "rabbit"=>{
           "host"=>"127.0.0.1"
       },
       "xvpvnc_proxy"=>{
           "bind_interface"=>"eth0"
       },
       "novnc_proxy"=>{
           "bind_interface"=>"eth0"
       },
       "network" => {
          "service_type" => "quantum"
        },
       "config" => {
           "ram_allocation_ratio" => 5.0
       },
       "libvirt" => { 
           "bind_interface"=>"lo",  
           "virt_type" => "qemu" 
       }    
    }
  }
  )
