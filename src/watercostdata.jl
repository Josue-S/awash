# need waternet
# this script breaks down

using DataFrames
using RData

# energy cost to lift 1000m3 by 1m
energycostperlift = 1.



### EXTRACTION COST
# sw: compute relative elevation if source downhill, 0 otherwise
# if missing information, default value is specified by naelev
if config["watercost-extraction"]
	naelev = 5.
	canalextractioncost = zeros(numcanals)
	for ii in 1:numcanals
		gauge_id = draws[ii,:gaugeid][(search(draws[ii,:gaugeid],".")[1]+1):end]
	
		indx = find(waternetdata["stations"][:colid] .== gauge_id)
		if length(indx) == 0
			canalextractioncost[ii] = naelev
		else
			if length(indx)>1
				indx = indx[find(waternetdata["stations"][indx,:collection] .== draws[ii,:gaugeid][1:(search(draws[ii,:gaugeid],".")[1]-1)])]
			end
			elevation_source = waternetdata["stations"][indx, :elev][1]
		
			county_id = draws[ii, :fips] < 10000 ? "0$(draws[ii, :fips])" : "$(draws[ii, :fips])"
			elevation_county = counties[:Elevation_ft][find(counties[:FIPS] .== county_id)][1] *0.305
			if isna(elevation_county) # if county-info does not have elevation information, use values from gw model
				elevation_county = readtable(datapath("gwmodel/county_elevation.txt"))[1][find(counties[:FIPS] .== county_id)][1]
			end

			if elevation_source < elevation_county
				canalextractioncost[ii] = elevation_county - elevation_source
			end
		end
	end

# gw: extraction cost prop to drawdown to watertable
	aquiferextractioncost = zeros(numcounties)
        drawdowndeepaquifer = readdlm(datapath("cost/drawdown0.txt"))
	fipsaquifer = readdlm(datapath("gwmodel/v_FIPS.txt"))
	for ii in 1:numcounties
                 county_id = parse(Float64, mastercounties[:fips][ii])
		 aquiferextractioncost[ii] = drawdowndeepaquifer[find(fipsaquifer .== county_id)][1]
	end
	aquiferextractioncost[find(aquiferextractioncost .<naelev)] = naelev

# compute costs
	canalextractioncost *= energycostperlift
	aquiferextractioncost *= energycostperlift
else
	canalextractioncost = ones(numcanals)
	aquiferextractioncost = 100*ones(numaquifers)
end

### TREATMENT COST
# treatment cost information at the county level
# in $ per 1000m3 treated
if config["watercost-treatment"]
	swtreatmentcost = 10*ones(numcounties)
	gwtreatmentcost = ones(numcounties)
else
	swtreatmentcost = zeros(numcounties)
	gwtreatmentcost = zeros(numcounties)
end

### DISTRIBUTION COST
# first model: only pressure cost (10m of lift)
distributioncost = 10. * energycostperlift * ones(numcounties)






