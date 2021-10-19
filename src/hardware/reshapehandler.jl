is_hardware_primitive(::Type{typeof(reshape)}, args...) = true
gethandler(::Type{typeof(reshape)}, args...) = reshape_handler

function reshape_handler(buffer, netlist, inputs, outputs)
    for input in inputs[2:end]
        delete!(netlist, input)
    end

    if issigned(inputs[1])
        setsigned!(netlist, outputs[1], true)
        write(buffer, """
            $stdcomment
            // BEGIN reshape
            assign $(name(outputs[1]))_p = $(name(inputs[1]))_p;
            assign $(name(outputs[1]))_m = $(name(inputs[1]))_m;
            // END reshape
            \n""")
    else
        write(buffer, """
            $stdcomment
            // BEGIN reshape
            assign $(name(outputs[1])) = $(name(inputs[1]));
            // END reshape
            \n""")
    end

    return buffer
end