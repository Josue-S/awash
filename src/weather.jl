# Can only be called after loading regionnet.jl

using NetCDF

statefips = ncread("../data/VIC_WB.nc", "state_fips")
countyfips = ncread("../data/VIC_WB.nc", "county_fips")
fips = map(fipsnum -> (fipsnum < 10000 ? "0$fipsnum" : "$fipsnum"), round(Int, statefips * 1000 + countyfips))

counties = readtable("../data/county-info.csv", eltypes=[UTF8String, UTF8String, UTF8String, UTF8String, Float64, Float64, Float64, Float64, Float64, Float64, Float64])
counties[:FIPS] = map(fips -> length(fips) == 4 ? "0$fips" : fips, counties[:FIPS])

function reorderfips(weather::DataArrays.DataArray{Float64, 1}, fromfips, tofips)
    result = zeros(length(tofips))
    for rr in 1:length(tofips)
        ii = findfirst(fromfips .== tofips[rr])
        if ii > 0
            result[rr] = weather[ii]
        end
    end

    result
end

counties[isna(counties[:, :TotalArea_sqmi]), :TotalArea_sqmi] = 0
countyareas = reorderfips(counties[:, :TotalArea_sqmi] * 258.999, counties[:FIPS], mastercounties[:fips]) # Ha
counties[isna(counties[:, :LandArea_sqmi]), :LandArea_sqmi] = 0
countylandareas = reorderfips(counties[:, :LandArea_sqmi] * 258.999, counties[:FIPS], mastercounties[:fips]) # Ha

function reorderfips(weather::Array{Float64, 2}, fromfips, tofips)
    result = zeros(length(tofips), size(weather, 1))
    for rr in 1:length(tofips)
        ii = findfirst(fromfips .== tofips[rr])
        if ii > 0
            result[rr, :] = weather[:, ii]
        end
    end

    result
end

function sum2timestep(weather)
    if config["timestep"] == 1
        return weather[:, config["startweather"]:end]
    end
    
    timesteps = round(Int64, (size(weather, 2) - config["startweather"] + 1) / config["timestep"])
    bytimestep = zeros(size(weather, 1), timesteps)
    for timestep in 1:timesteps
        allcounties = zeros(size(weather, 1))
        for month in 1:config["timestep"]
            allcounties += weather[:, round(Int64, (timestep - 1) * config["timestep"] + month + config["startweather"] - 1)]
        end

        bytimestep[:, timestep] = allcounties
    end

    bytimestep
end

# Load data from the water budget
# Currently summing over all months
runoff = sum2timestep(reorderfips(getweather("runoff"), fips, mastercounties[:fips])); # mm / timestep
precip = sum2timestep(reorderfips(getweather("precip"), fips, mastercounties[:fips])); # mm / timestep

# Convert runoff to a gauge measure
waternetdata = read_rda("../data/waternet.RData", convertdataframes=true);
stations = waternetdata["stations"];

XX = spzeros(numgauges, numcounties) # contributions
# Fill in XX by column, with columns summing to 1
for rr in 1:numcounties
    if isna(countyareas[rr])
        continue
    end
    fips = parse(Int64, mastercounties[rr, :fips])
    countygauges = draws[draws[:fips] .== fips, :gaugeid]
    countyindexes = [gaugeid in keys(wateridverts) ? vertex_index(wateridverts[gaugeid]) : 0 for gaugeid in countygauges]
    gauges = convert(Vector{Int64}, countyindexes)

    invalids = gauges .== 0
    gauges[invalids] = nrow(stations) + 1
    stationareas = stations[gauges[gauges .<= nrow(stations)], :area]
    if length(stationareas) == 0
        continue
    end

    medarea = median(dropna(stationareas))
    allareas = ones(length(gauges))
    allareas[gauges .<= nrow(stations)] = stationareas
    allareas[isnan(allareas)] = 1

    XX[gauges, rr] = (allareas / sum(allareas)) * countyareas[rr] / 1000 # mm Ha to 1000 m^3
end

addeds = XX * runoff;
