# The reservoir component
#
# Manages the storage in reservoirs over time
using Mimi
using Distributions

reservoirdata = readtable(loadpath("reservoirs/allreservoirs.csv"))

@defcomp Reservoir begin
	reservoirs = Index()
	gauges = Index()
	# Streamflow connections from optim
	inflowsgauges = Parameter(index=[gauges, time], unit="1000 m^3")
	outflowsgauges = Parameter(index=[gauges, time], unit="1000 m^3")
	captures = Parameter(index=[reservoirs, time], unit="1000 m^3") # positive or negative
	# Reservoir inflows
	inflows = Variable(index=[reservoirs, time], unit="m^3")
	outflows = Variable(index=[reservoirs, time], unit="m^3")
	# withdrawals
	withdrawals = Variable(index=[reservoirs, time], unit="m^3")
	# releases
	releases = Variable(index=[reservoirs, time], unit="m^3")

	# Evaporation
	evaporation = Parameter(index=[reservoirs, time], unit="m^3")

	# Storage
	storage = Variable(index=[reservoirs, time], unit="m^3")
	storage0 = Parameter(index=[reservoirs], unit="m^3")
	storagecapacitymin = Parameter(index=[reservoirs], unit="m^3")
	storagecapacitymax = Parameter(index=[reservoirs], unit="m^3")
end

"""
Compute the storage for the reservoirs, the releases and the withdrawals from the reservoirs as they change in time
"""
function run_timestep(c::Reservoir, tt::Int)
	v = c.Variables
	p = c.Parameters
	d = c.Dimensions

	v.inflows[:,tt] = zeros(numreservoirs);
	v.outflows[:,tt] = zeros(numreservoirs);

	for gg in 1:numgauges
		index = vertex_index(downstreamorder[gg])
		if isreservoir[index] > 0
			rr = isreservoir[index]
			v.inflows[rr,tt] = p.inflowsgauges[gg, tt]*1000.;
			v.outflows[rr,tt] = p.outflowsgauges[gg, tt]*1000.;
		end
	end


	for rr in d.reservoirs
		if tt==1
			v.storage[rr,tt] = (1-p.evaporation[rr,tt])^config["timestep"]*p.storage0[rr] + p.captures[rr, tt]
		else
			v.storage[rr,tt] = (1-p.evaporation[rr,tt])^config["timestep"]*v.storage[rr,tt-1] + p.captures[rr, tt]
		end

		if p.captures[rr,tt]<0
			v.withdrawals[rr,tt] = -p.captures[rr,tt] - (v.outflows[rr,tt] - v.inflows[rr,tt])
			if v.inflows[rr,tt]<v.outflows[rr,tt]
				v.releases[rr,tt] = v.outflows[rr,tt] - v.inflows[rr, tt]
			else
				v.releases[rr,tt] = 0
			end
		else
			v.releases[rr,tt] = 0
			v.withdrawals[rr,tt] = 0
		end
	end
end

function initreservoir(m::Model, name=nothing)
    if name == nothing
        reservoir = addcomponent(m, Reservoir)
    else
        reservoir = addcomponent(m, Reservoir, name)
    end

    reservoir[:captures] = zeros(numreservoirs, numsteps);

    if config["dataset"] == "three"
        reservoir[:storagecapacitymax] = 8.2*ones(numreservoirs)
        reservoir[:storagecapacitymin] = 0.5*ones(numreservoirs)
        reservoir[:storage0] = 1.3*ones(numreservoirs)
        reservoir[:evaporation] = 0.01*ones(numreservoirs, numsteps)
    elseif "rescap" in keys(config) && config["rescap"] == "zero"
        reservoir[:storagecapacitymax] = zeros(numreservoirs);
       	reservoir[:storagecapacitymin] = zeros(numreservoirs);
       	reservoir[:storage0] = zeros(numreservoirs);
     	reservoir[:evaporation] = zeros(numreservoirs, numsteps);
    else
        rcmax = convert(Vector{Float64}, reservoirdata[:MAXCAP])
     	rcmax = rcmax*1233.48
     	reservoir[:storagecapacitymax] = rcmax;
     	reservoir[:storagecapacitymin] = zeros(numreservoirs);
        reservoir[:storage0] = rcmax*0.;
   	reservoir[:evaporation] = 0.05*ones(numreservoirs,numsteps);
        if "reshalf" in keys(config) && config["reshalf"] == "half"
            reservoir[:storage0] = (rcmax-0.1*rcmax)/2; #half full
        end
    end

    reservoir[:captures] = cached_fallback("extraction/captures", () -> zeros(numreservoirs, numsteps));
    reservoir[:outflowsgauges] = zeros(numgauges,numsteps);
    reservoir[:inflowsgauges] = zeros(numgauges,numsteps);

    reservoir
end


function grad_reservoir_outflows_captures(m::Model)
    function generate(A)
        # Fill in GAUGES x RESERVOIRS matrix
        # Propogate in downstream order
	for hh in 1:numgauges
	    gg = vertex_index(downstreamorder[hh])
	    gauge = downstreamorder[hh].label
	    for upstream in out_neighbors(wateridverts[gauge], waternet)
		index = vertex_index(upstream, waternet)
		println(index)
		if isreservoir[index] > 0
		    A[gg, isreservoir[index]] = -1
		else
		    A[gg, :] += A[index, :]
		end
	    end
	end
    end
    roomintersect(m, :WaterNetwork, :outflows, :Reservoir, :captures, generate, [:time], [:time])
end

function grad_reservoir_storage_captures(m::Model)
    roomchunks(m, :Reservoir, :storage, :captures, (vtt, ptt) -> ifelse(vtt >= ptt, spdiagm((1-m.external_parameters[:evaporation].values[:, vtt]).^(config["timestep"]*(vtt-ptt)), 0), spzeros(numreservoirs, numreservoirs)), [:time], [:time])
end

function constraintoffset_reservoir_storagecapacitymin(m::Model)
    gen(rr) = m.external_parameters[:storagecapacitymin].values[rr]
    hallsingle(m, :Reservoir, :storage, gen, [:time])
end

function constraintoffset_reservoir_storagecapacitymax(m::Model)
    gen(rr) = m.external_parameters[:storagecapacitymax].values[rr]
    hallsingle(m, :Reservoir, :storage, gen, [:time])
end

function constraintoffset_reservoir_storage0(m::Model)
    gen(rr, tt) = (1-m.external_parameters[:evaporation].values[rr])^(tt*config["timestep"]) * m.external_parameters[:storage0].values[rr]
    hallsingle(m, :Reservoir, :storage, gen)
end

