using Mimi
using OptiMimi
include("lib/readconfig.jl")
include("lib/datastore.jl")


config = readconfig("../configs/standard-60year-colorado.yml");
suffix = getsuffix()

include("optimizationcst.jl")
#include("optimization-colorado-fixedarea.jl")

using MathProgBase
@time sol = linprog(-house.f, house.A, '<', house.b, house.lowers, house.uppers)

coning = constraining(house, convert(Vector{Float64}, sol.sol))

rdf = DataFrame(fips=mastercounties[:fips]);
cdf = DataFrame(fips=repmat(mastercounties[:fips], numcrops), crop=vec(repeat(crops, inner=[numcounties, 1])));

# Look at parameter values
varlens = varlengths(m, house.paramcomps, house.parameters)
for ii in 1:length(house.parameters)
    println(house.parameters[ii])
    index1 = sum(varlens[1:ii-1]) + 1
    index2 = sum(varlens[1:ii])

    values = sol.sol[index1:index2]

    if varlens[ii] == nrow(rdf)
        rdf[house.parameters[ii]] = values
    elseif varlens[ii] == nrow(cdf)
        cdf[house.parameters[ii]] = values
    else
        #println("Cannot store: $(varlens[ii])")
    end

    if (sum(values .!= 0) == 0)
        println("All zero.")
    else
        println(values[1:min(100, index2 - index1 + 1)])
        println("Sum: $(sum(values))")
    end
end

serialize(open("../data/extraction/waterfromgw$suffix.jld", "w"), reshape(sol.sol[sum(varlens[1])+1:sum(varlens[1:2])], numcounties, numsteps)) #should be 756
serialize(open("../data/extraction/supersource$suffix.jld", "w"), reshape(sol.sol[1:varlens[1]], numcounties, numsteps))
#756
serialize(open("../data/extraction/withdrawals$suffix.jld", "w"), reshape(sol.sol[sum(varlens[1:2])+1:sum(varlens[1:3])], numcanals, numsteps))
#should be 11532
serialize(open("../data/extraction/rainfedareas$suffix.jld", "w"), reshape(sol.sol[sum(varlens[1:3])+1:sum(varlens[1:4])], numcounties,numcrops))
#should be 6804
serialize(open("../data/extraction/irrigatedareas$suffix.jld", "w"), reshape(sol.sol[sum(varlens[1:4])+1:sum(varlens[1:5])], numcounties,numcrops))
#should be 6804


# Get constraint values
constvalues = house.A * sol.sol

varlens = varlengths(m, house.constcomps, house.constraints)
for ii in 1:length(house.constraints)
    println(house.constraints[ii])
    index1 = sum(varlens[1:ii-1]) + 1
    index2 = sum(varlens[1:ii])

    values = constvalues[index1:index2]

    if varlens[ii] == nrow(rdf)
        rdf[house.constraints[ii]] = values
    elseif varlens[ii] == nrow(cdf)
        cdf[house.constraints[ii]] = values
    else
        #println("Cannot store: $(varlens[ii])")
    end

    if (sum(values .!= 0) == 0)
        println("All zero.")
    else
        println(values[1:min(100, index2 - index1 + 1)])
    end
end

writetable("../results/regionout.csv", rdf)
writetable("../results/cropsout.csv", cdf)
print("Total production")
println(round(constvalues[sum(varlens[1:(end-1)])+1:end]))