const stdcomment = "// Autogenerated by BitSAD"

function gethandler end
gethandler(::Bool, args...) = gethandler(args...)

is_hardware_primitive(sig...) = is_trace_primitive(sig...)

function generatehw(f, args...;
                    top = _nameof(f),
                    submodules = [],
                    transforms = [constantreduction!])
    # get tape and transform
    tape = trace(f, args...;
                 isprimitive = is_hardware_primitive,
                 submodules = submodules)
    transform!(_squash_binary_vararg, tape)

    # extract tape into module
    m = Module(fn = f, name = top)
    extracttrace!(m, tape)

    # apply transformations
    foreach(t! -> t!(m), transforms)

    # replace constants with Verilog strings
    constantreplacement!(m)

    # generate verilog string
    return generateverilog(m), m
end

_getstructname(::T) where T = lowercase(string(nameof(T)))

function _handle_getproperty!(m::Module, call, param_map, const_map)
    if m.fn == _gettapeval(call.args[1])
        val = _gettapeval(call)
        prop = string(_gettapeval(call.args[2]))
        m.parameters[prop] = string(val)
        param_map[Ghost.Variable(call)] = prop
    else
        const_map[Ghost.Variable(call)] = string(_gettapeval(call))
    end

    return m
end

function extracttrace!(m::Module, tape::Ghost.Tape)
    param_map = Dict{Ghost.Variable, String}()
    const_map = Dict{Ghost.Variable, String}()
    # skip first call which is the function being compiled
    for call in tape
        if call isa Ghost.Call
            # ignore materialize calls
            (call.fn == Base.materialize) && continue

            # handle calls to getproperty
            if call.fn == Base.getproperty
                _handle_getproperty!(m, call, param_map, const_map)
                continue
            end

            # create Operator for Ghost.Call (handling broadcast)
            # structs are renamed as Foo -> foo_$id
            # plain functions are name ""
            name = _isstruct(call.fn) ? _getstructname(call.fn) * "_$(call.fn.id)" : ""
            isbroadcast = _isbcast(call.fn)
            fn = isbroadcast ? _gettapeval(call.args[1]) : call.fn
            op = (name = Symbol(name), type = typeof(fn), broadcasted = isbroadcast)

            # map inputs and outputs of Ghost.Call to Nets
            # set args that are Ghost.Input to :input class
            inputs = map(call.args[(1 + isbroadcast):end]) do arg
                val = _gettapeval(arg)
                name = haskey(param_map, arg) ? param_map[arg] :
                       haskey(const_map, arg) ? const_map[arg] :
                       _isvariable(arg) ? "net_$(arg.id)" : string(val)
                net = Net(val; name = name)

                if _isvariable(arg)
                    if _isinput(arg)
                        net = setclass(net, :input)
                    elseif haskey(param_map, arg)
                        net = setclass(net, :parameter)
                    elseif haskey(const_map, arg)
                        net = setclass(net, :constant)
                    end
                else # treat all non-variables as constants
                    net = setclass(net, :constant)
                end

                return net
            end
            outval = isbroadcast ? Base.materialize(_gettapeval(call)) : _gettapeval(call)
            output = Net(outval; name = "net_$(call.id)")

            if tape.result == Ghost.Variable(call)
                output = setclass(output, :output)
            end

            addnode!(m, inputs, [output], op)
        end
    end

    return m
end
