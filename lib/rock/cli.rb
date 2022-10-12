require 'tty-prompt'

module Rock
    module CLI
        def self.choose_orocos_task_and_port(name_service: Orocos.name_service, task_name: nil, port_name: nil)
            prompt = TTY::Prompt.new

            prompt.on(:keyctrl_x, :keyescape, :keyctrl_c) do
                puts "\nExiting..."
                exit
            end

            if task_name
                begin
                    selected_task = Orocos.get(task_name)
                rescue Orocos::NotFound
                end
                candidates = name_service.names.grep(/(^|\/)#{task_name}/).sort
                if candidates.empty?
                    STDERR.puts "No task matches #{task_name}, and none start with #{task_name}"
                    return
                end
                if candidates.size == 1
                    task_name = candidates.first
                else
                    task_name = prompt.select("Select a task", candidates)
                end
            end

            if !task_name
                tasks = name_service.names
                if tasks.empty?
                    STDERR.puts "No tasks available"
                    return
                end
                task_name = prompt.select("Select a task", tasks)
            end
            selected_task ||= Orocos.get(task_name)

            if !port_name
                ports = selected_task.each_port.
                    find_all { |p| p.respond_to?(:reader) }
                ports = Hash[ports.map { |p| [p.name, p] }]
                prompt.select("Select a port", ports)
            else
                selected_task.port(port_name)
            end
        end
    end
end

