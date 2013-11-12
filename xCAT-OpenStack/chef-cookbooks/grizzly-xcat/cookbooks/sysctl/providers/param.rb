def load_current_resource
  new_resource.key new_resource.name unless new_resource.key
end

action :apply do
  key_path = new_resource.key.split('.')
  sys_attrs = Mash.new(node.default['sysctl']['params'].to_hash)
  location = key_path.slice(0, key_path.size - 1).inject(sys_attrs) do |m, o|
    m[o] ||= {}
    m[o]
  end
  unless(location[key_path.last] == new_resource.value)
    location[key_path.last] = new_resource.value
    execute "sysctl[#{new_resource.key}]" do
      command "sysctl -w #{new_resource.key}=#{new_resource.value}"
      not_if do
        %x{sysctl -n #{new_resource.key}}.strip == new_resource.value.to_s
      end
    end
    node.default['sysctl']['params'] = sys_attrs
    new_resource.updated_by_last_action(true)
  end
end

action :remove do
  key_path = new_resource.key.split('.')
  sys_attrs = Mash.new(node.default['sysctl']['params'].to_hash)
  location = key_path.slice(0, key_path.size - 1).inject(sys_attrs) do |m, o|
    m.nil? ? nil : m[o]
  end
  if(location && location[key_path.last])
    location.delete(key_path.last)
    if(location.empty?)
      key_path.size.times do |i|
        int_key = key_path.size - i - 1
        l = key_path.slice(0, int_key).inject(node['sysctl']['params']) do |m, o|
          m.nil? ? nil : m[o]
        end
        if(l && l[key_path[int_key]] && l[key_path[int_key]].empty?)
          l.delete(key_path[int_key])
        end
      end
    end
    node.default['sysctl']['params'] = sys_attrs
    new_resource.updated_by_last_action(true)
  end
end
