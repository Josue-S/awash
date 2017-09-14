include("../../src/lib/readconfig.jl")
config = readconfig("../../configs/standard-1year.yml")

include("../../src/world.jl")
include("../../src/lib/agriculture-ers.jl")

crops = ["corn", "soyb", "whea", "sorg", "barl"] #"cott", "rice", "oats", "pean"

value = repmat([0.0], size(masterregions, 1))
maxvalue = repmat(["none"], size(masterregions, 1))
profit = repmat([0.0], size(masterregions, 1))
maxprofit = repmat(["none"], size(masterregions, 1))
for crop in crops
    data = ers_information(crop, "Opportunity cost of land", 2010; includeus=false)
    data[isna(data)] = 0
    data = convert(Vector{Float64}, data)

    maxvalue[data .> value] = crop
    value = max(value, data)

    data = ers_information(crop, "revenue", 2010; includeus=false) - ers_information(crop, "cost", 2010; includeus=false)
    data[isna(data)] = 0
    data = convert(Vector{Float64}, data)

    maxprofit[data .> profit] = crop
    profit = max(profit, data)
end

masterregions[:farmvalue] = value
masterregions[:valuesource] = maxvalue
masterregions[:profit] = profit
masterregions[:profitsource] = maxprofit

writetable("farmvalue.csv", masterregions)