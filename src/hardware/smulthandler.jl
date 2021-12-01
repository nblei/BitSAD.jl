@kwdef mutable struct SMultHandler
    id::Int = 0
    broadcasted::Bool
end

@kwdef mutable struct SMatMultHandler
    id::Int = 0
end

gethandler(::Bool, ::Type{typeof(*)}, ::Type{<:SBitstream}, ::Type{<:SBitstream}) =
    SMultHandler(broadcasted = false)

gethandler(broadcasted::Bool,
           ::Type{typeof(*)},
           ::Type{<:AbstractArray{<:SBitstream}},
           ::Type{<:AbstractArray{<:SBitstream}}) =
    broadcasted ? SMultHandler(broadcasted = true) : SMatMultHandler()

function (handler::SMultHandler)(buffer, netlist, inputs, outputs)
    # update netlist with inputs
    setsigned!(netlist, inputs[1], true)
    setsigned!(netlist, inputs[2], true)

    # compute output size
    lname, rname = handle_broadcast_name(name(inputs[1]), name(inputs[2]),
                                         netsize(inputs[1]), netsize(inputs[2]))
    outsize = netsize(outputs[1])

    broadcast = handler.broadcasted ? "_bcast" : ""

    # add internal nets to netlist
    push!(netlist, Net(name = "mult$(broadcast)$(handler.id)_out_pp", size = outsize))
    push!(netlist, Net(name = "mult$(broadcast)$(handler.id)_out_pm", size = outsize))
    push!(netlist, Net(name = "mult$(broadcast)$(handler.id)_out_mp", size = outsize))
    push!(netlist, Net(name = "mult$(broadcast)$(handler.id)_out_mm", size = outsize))
    push!(netlist, Net(name = "mult$(broadcast)$(handler.id)_out_11", size = outsize))
    push!(netlist, Net(name = "mult$(broadcast)$(handler.id)_out_12", size = outsize))
    push!(netlist, Net(name = "mult$(broadcast)$(handler.id)_out_13", size = outsize))
    push!(netlist, Net(name = "mult$(broadcast)$(handler.id)_out_14", size = outsize))

    # add output net to netlist
    setsigned!(netlist, outputs[1], true)

    write(buffer, """
        $stdcomment
        // BEGIN mult$(broadcast)$(handler.id)
        assign mult$(broadcast)$(handler.id)_out_pp = $(lname("_p")) & $(rname("_p"))
        assign mult$(broadcast)$(handler.id)_out_pm = $(lname("_p")) & $(rname("_m"))
        assign mult$(broadcast)$(handler.id)_out_mp = $(lname("_m")) & $(rname("_p"))
        assign mult$(broadcast)$(handler.id)_out_mm = $(lname("_m")) & $(rname("_m"))
        stoch_sat_sub_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mult$(broadcast)$(handler.id)_11 (
                .CLK(CLK),
                .nRST(nRST),
                .A(mult$(broadcast)$(handler.id)_out_pp),
                .B(mult$(broadcast)$(handler.id)_out_pm),
                .Y(mult$(broadcast)$(handler.id)_out_11)
            );
        stoch_sat_sub_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mult$(broadcast)$(handler.id)_12 (
                .CLK(CLK),
                .nRST(nRST),
                .A(mult$(broadcast)$(handler.id)_out_pm),
                .B(mult$(broadcast)$(handler.id)_out_pp),
                .Y(mult$(broadcast)$(handler.id)_out_12)
            );
        stoch_sat_sub_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mult$(broadcast)$(handler.id)_13 (
                .CLK(CLK),
                .nRST(nRST),
                .A(mult$(broadcast)$(handler.id)_out_mp),
                .B(mult$(broadcast)$(handler.id)_out_mm),
                .Y(mult$(broadcast)$(handler.id)_out_13)
            );
        stoch_sat_sub_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mult$(broadcast)$(handler.id)_14 (
                .CLK(CLK),
                .nRST(nRST),
                .A(mult$(broadcast)$(handler.id)_out_mm),
                .B(mult$(broadcast)$(handler.id)_out_mp),
                .Y(mult$(broadcast)$(handler.id)_out_14)
            );
        stoch_add_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mult$(broadcast)$(handler.id)_p (
                .CLK(CLK),
                .nRST(nRST),
                .A(mult$(broadcast)$(handler.id)_out_11),
                .B(mult$(broadcast)$(handler.id)_out_14),
                .Y($(name(outputs[1]))_p)
            );
        stoch_add_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mult$(broadcast)$(handler.id)_m (
                .CLK(CLK),
                .nRST(nRST),
                .A(mult$(broadcast)$(handler.id)_out_12),
                .B(mult$(broadcast)$(handler.id)_out_13),
                .Y($(name(outputs[1]))_m)
            );
        // END mult$(broadcast)$(handler.id)
        \n""")

    handler.id += 1

    return buffer
end

function (handler::SMatMultHandler)(buffer, netlist, inputs, outputs)
    # update netlist with inputs
    setsigned!(netlist, inputs[1], true)
    setsigned!(netlist, inputs[2], true)

    # compute output size
    m, n = netsize(inputs[1])
    _, p = netsize(inputs[2])
    outsize = netsize(outputs[1])

    # add output net to netlist
    setsigned!(netlist, outputs[1], true)

    # add internal nets to netlist
    push!(netlist, Net(name = "mmult$(handler.id)_out_pp", size = outsize))
    push!(netlist, Net(name = "mmult$(handler.id)_out_pm", size = outsize))
    push!(netlist, Net(name = "mmult$(handler.id)_out_mp", size = outsize))
    push!(netlist, Net(name = "mmult$(handler.id)_out_mm", size = outsize))
    push!(netlist, Net(name = "mmult$(handler.id)_out_11", size = outsize))
    push!(netlist, Net(name = "mmult$(handler.id)_out_12", size = outsize))
    push!(netlist, Net(name = "mmult$(handler.id)_out_13", size = outsize))
    push!(netlist, Net(name = "mmult$(handler.id)_out_14", size = outsize))

    write(buffer, """
        $stdcomment
        // BEGIN mmult$(handler.id)
        stoch_matrix_mult #(
                .NUM_ROWS($m),
                .NUM_MID($n),
                .NUM_COLS($p)
            ) mmult$(handler.id)_pp (
                .CLK(CLK),
                .nRST(nRST),
                .A($(name(inputs[1]))_p),
                .B($(name(inputs[2]))_p),
                .Y(mmult$(handler.id)_out_pp)
            );
        stoch_matrix_mult #(
                .NUM_ROWS($m),
                .NUM_MID($n),
                .NUM_COLS($p)
            ) mmult$(handler.id)_pm (
                .CLK(CLK),
                .nRST(nRST),
                .A($(name(inputs[1]))_p),
                .B($(name(inputs[2]))_m),
                .Y(mmult$(handler.id)_out_pm)
            );
        stoch_matrix_mult #(
                .NUM_ROWS($m),
                .NUM_MID($n),
                .NUM_COLS($p)
            ) mmult$(handler.id)_mp (
                .CLK(CLK),
                .nRST(nRST),
                .A($(name(inputs[1]))_m),
                .B($(name(inputs[2]))_p),
                .Y(mmult$(handler.id)_out_mp)
            );
        stoch_matrix_mult #(
                .NUM_ROWS($m),
                .NUM_MID($n),
                .NUM_COLS($p)
            ) mmult$(handler.id)_mm (
                .CLK(CLK),
                .nRST(nRST),
                .A($(name(inputs[1]))_m),
                .B($(name(inputs[2]))_m),
                .Y(mmult$(handler.id)_out_mm)
            );
        stoch_sat_sub_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mmult$(handler.id)_11 (
                .CLK(CLK),
                .nRST(nRST),
                .A(mmult$(handler.id)_out_pp),
                .B(mmult$(handler.id)_out_pm),
                .Y(mmult$(handler.id)_out_11)
            );
        stoch_sat_sub_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mmult$(handler.id)_12 (
                .CLK(CLK),
                .nRST(nRST),
                .A(mmult$(handler.id)_out_pm),
                .B(mmult$(handler.id)_out_pp),
                .Y(mmult$(handler.id)_out_12)
            );
        stoch_sat_sub_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mmult$(handler.id)_13 (
                .CLK(CLK),
                .nRST(nRST),
                .A(mmult$(handler.id)_out_mp),
                .B(mmult$(handler.id)_out_mm),
                .Y(mmult$(handler.id)_out_13)
            );
        stoch_sat_sub_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mmult$(handler.id)_14 (
                .CLK(CLK),
                .nRST(nRST),
                .A(mmult$(handler.id)_out_mm),
                .B(mmult$(handler.id)_out_mp),
                .Y(mmult$(handler.id)_out_14)
            );
        stoch_add_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mmult$(handler.id)_p (
                .CLK(CLK),
                .nRST(nRST),
                .A(mmult$(handler.id)_out_11),
                .B(mmult$(handler.id)_out_14),
                .Y($(name(outputs[1]))_p)
            );
        stoch_add_mat #(
                .NUM_ROWS($(outsize[1])),
                .NUM_COLS($(outsize[2]))
            ) mmult$(handler.id)_m (
                .CLK(CLK),
                .nRST(nRST),
                .A(mmult$(handler.id)_out_12),
                .B(mmult$(handler.id)_out_13),
                .Y($(name(outputs[1]))_m)
            );
        // END mmult$(handler.id)
        \n""")

    handler.id += 1

    return buffer
end