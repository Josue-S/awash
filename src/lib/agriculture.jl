using DataFrames
include("agriculture-ers.jl")

## Univariate crop parametrs
unicrop_irrigationstress = Dict("barley" => 95.2, "corn" => 73.1,
                                "corn.co.rainfed" => 0,"corn.co.irrigated"=>73.1,
                                "wheat.co.rainfed" => 0, "wheat.co.irrigated"=>7.4,
                                "sorghum" => 19.2 / 1.1364914374721, "soybeans" => 0.,#"sorghum" => 0., "soybeans" => 0.,
                                "wheat" => 7.4, "hay" => 10.) # (mm/year) / m-deficiency

unicrop_irrigationrate = Dict("barley" => 315.8, "corn" => 13.0,
                              "sorghum" => 19.2, "soybeans" => 330.2,
                              "wheat" => 21.4, "hay" => 386.1,
                         "corn.co.rainfed" => 0,"corn.co.irrigated" => 1.6 * 304.8,
                   "wheat.co.rainfed" => 0,"wheat.co.irrigated" => 1.9 * 304.8
    ) # mm/year



## Barley: consistent ~94% irrigated, say at 19 in. when full water stress
## Sorghum: Variable 9 - 18% irrigated (.7 ft/acre), so say half intercept half stress
## Soybeans: Used 13 inches (https://www.ksre.k-state.edu/irrigate/oow/p08/Schneekloth08.pdf)
## Hay: About 80% irrigated, and Colorado average is 19 inches for irrigated
## Corn and Wheat not used as unicrops, but using the below.

known_irrigationrate = Dict("corn.co.rainfed" => 0,
                            "corn.co.irrigated" => 1.6 * 304.8, # convert ft -> mm
                            "wheat.co.rainfed" => 0,
                            "wheat.co.irrigated" => 1.9 * 304.8) # convert ft -> mm

# Irrigation crop parameters
water_requirements = Dict("alfalfa" => 1.63961100235402, "otherhay" => 1.63961100235402,
                          "Barley" => 1.18060761343329, "Barley.Winter" => 1.18060761343329,
                          "Maize" => 1.47596435526564,
                          "Sorghum" => 1.1364914374721,
                          "Soybeans" => 1.37599595071683,
                          "Wheat" => 0.684836198198068, "Wheat.Winter" => 0.684836198198068,
                          "barley" => 1.18060761343329, "corn" => 1.47596435526564,
                          "sorghum" => 1.1364914374721, "soybeans" => 1.37599595071683,
                          "wheat" => 0.684836198198068, "hay" => 1.63961100235402,
                          "wheat.co.rainfed" =>  0.684836198198068,  "wheat.co.irrigated" =>  0.684836198198068,
                          "corn.co.rainfed" => 1.47596435526564,  "corn.co.irrigated" => 1.47596435526564) # in m

# Per year costs
cultivation_costs = Dict("alfalfa" => 306., "otherhay" => 306., "Hay" => 306,
                         "Barley" => 442., "Barley.Winter" => 442.,
                         "Maize" => 554., "Sorghum" => 314.,
                         "Soybeans" => 221., "Wheat" => 263., "Wheat.Winter" => 263., "barley" => 442.,
                         "corn" => 554., "corn.co.rainfed" => 554., "corn.co.irrigated" => 554.,
                         "sorghum" => 314., "soybeans" => 221.,
                         "wheat" => 263., "wheat.co.rainfed" => 263., "wheat.co.irrigated" => 263,
                         "hay" => 306.) # USD / acre

maximum_yields = Dict("alfalfa" => 25., "otherhay" => 25., "Hay" => 4., "hay" => 4.,
                      "Barley" => 135., "Barley.Winter" => 135., "barley" => 135.0,
                      "Maize" => 160., "corn" => 160.,
                      "corn.co.rainfed" => 160,  "corn.co.irrigated" => 160,
                      "Sorghum" => 50., "sorghum" => 50.,
                      "Soybeans" => 20., "soybeans" => 20.,
                      "Wheat" => 100., "Wheat.Winter" => 100., "wheat" => 100.,
                      "wheat.co.rainfed" => 100,  "wheat.co.irrigated" => 100)

crop_prices = Dict("alfalfa" => 102.51 / 2204.62, # alfalfa
                   "otherhay" => 102.51 / 2204.62, # otherhay
                   "Barley" => 120.12 * .021772, # barley
                   "Barley.Winter" => 120.12 * .021772, # barley.winter
                   "Maize" => 160.63 * .0254, # maize
                   "Sorghum" => 174.90 / 2204.62, # sorghum: $/MT / lb/MT
                   "Soybeans" => 349.52 * .0272155, # soybeans
                   "Wheat" => 5.1675, # wheat
                   "Wheat.Winter" => 171.50 * .0272155) # wheat.winter

quickstats_planted = Dict("corn.co.rainfed" => "agriculture/allyears/maize-nonirrigated-planted.csv",
                          "corn.co.irrigated" => "agriculture/allyears/maize-irrigated-planted.csv",
                          "wheat.co.rainfed" => "agriculture/allyears/wheat-nonirrigated-planted.csv",
                          "wheat.co.irrigated" => "agriculture/allyears/wheat-irrigated-planted.csv")

type StatisticalAgricultureModel
    intercept::Float64
    interceptse::Float64
    gdds::Float64
    gddsse::Float64
    kdds::Float64
    kddsse::Float64
    wreq::Float64
    wreqse::Float64

    gddoffset::Float64
    kddoffset::Float64
end

function StatisticalAgricultureModel(df::DataFrame, filter::Symbol, fvalue::Any)
    interceptrow = findfirst((df[filter] .== fvalue) .& (df[:coef] .== "intercept"))
    gddsrow = findfirst((df[filter] .== fvalue) .& (df[:coef] .== "gdds"))
    kddsrow = findfirst((df[filter] .== fvalue) .& (df[:coef] .== "kdds"))
    wreqrow = findfirst((df[filter] .== fvalue) .& (df[:coef] .== "wreq"))
    gddoffsetrow = findfirst((df[filter] .== fvalue) .& (df[:coef] .== "gddoffset"))
    kddoffsetrow = findfirst((df[filter] .== fvalue) .& (df[:coef] .== "kddoffset"))

    if interceptrow > 0
        intercept = df[interceptrow, :mean]
        interceptse = df[interceptrow, :serr]
    else
        intercept = 0
        interceptse = 0
    end

    gdds = gddsrow != 0 ? df[gddsrow, :mean] : 0
    gddsse = gddsrow != 0 ? df[gddsrow, :serr] : Inf
    kdds = kddsrow != 0 ? df[kddsrow, :mean] : 0
    kddsse = kddsrow != 0 ? df[kddsrow, :serr] : Inf
    wreq = wreqrow != 0 ? df[wreqrow, :mean] : 0
    wreqse = wreqrow != 0 ? df[wreqrow, :serr] : Inf
    gddoffset = gddoffsetrow != 0 ? df[gddoffsetrow, :mean] : 0
    kddoffset = kddoffsetrow != 0 ? df[kddoffsetrow, :mean] : 0

    StatisticalAgricultureModel(intercept, interceptse, gdds, gddsse, kdds, kddsse, wreq, wreqse, gddoffset, kddoffset)
end

function gaussianpool(mean1, sdev1, mean2, sdev2)
    if isna.(sdev1) || isnan.(sdev1)
        mean2, sdev2
    elseif isna.(sdev2) || isnan.(sdev2)
        mean1, sdev1
    else
        (mean1 / sdev1^2 + mean2 / sdev2^2) / (1 / sdev1^2 + 1 / sdev2^2), 1 / (1 / sdev1^2 + 1 / sdev2^2)
    end
end

function fallbackpool(meanfallback, sdevfallback, mean1, sdev1)
    if isna.(mean1)
        meanfallback, sdevfallback
    else
        mean1, sdev1
    end
end

function findcroppath(prefix, crop, suffix, recurse=true)
    println(prefix * crop * suffix)
    if isfile(loadpath(prefix * crop * suffix))
        return loadpath(prefix * crop * suffix)
    end

    if isupper(crop[1]) && isfile(loadpath(prefix * lcfirst(crop) * suffix))
        return loadpath(prefix * lcfirst(crop) * suffix)
    end

    if islower(crop[1]) && isfile(loadpath(prefix * ucfirst(crop) * suffix))
        return loadpath(prefix * ucfirst(crop) * suffix)
    end

    if !recurse
        return nothing
    end

    croptrans = Dict{AbstractString, Vector{AbstractString}}("corn" => ["maize"], "hay" => ["otherhay"], "maize" => ["corn"])
    if lowercase(crop) in keys(croptrans)
        for crop2 in croptrans[lowercase(crop)]
            path2 = findcroppath(prefix, crop2, suffix, false)
            if path2 != nothing
                return path2
            end
        end
    end

    return nothing
end

if isfile(cachepath("agmodels.jld")) ## this might cause issues when juggling between two set-ups Colorado or other. Maybe a suffix should be added?
    println("Loading from saved region network...")

    agmodels = deserialize(open(cachepath("agmodels.jld"), "r"));
else
    # Prepare all the agricultural models
    agmodels = Dict{String, Dict{String, StatisticalAgricultureModel}}() # {crop: {fips: model}}
    nationals = readtable(joinpath(loadpath("agriculture/nationals.csv")))
    nationalcrop = Dict{String, String}("barley" => "Barley", "corn" => "Maize",
                                        "sorghum" => "Sorghum", "soybeans" => "Soybeans",
                                        "wheat" => "Wheat", "hay" => "alfalfa")

    for crop in allcrops
        println(crop)
        agmodels[crop] = Dict{Int64, StatisticalAgricultureModel}()

        # Create the national model
        national = StatisticalAgricultureModel(nationals, :crop, get(nationalcrop, crop, crop))
        bayespath = nothing #findcroppath("agriculture/bayesian/", crop, ".csv")
        if bayespath != nothing
            counties = readtable(bayespath)
            combiner = fallbackpool
        else
            croppath = findcroppath("agriculture/unpooled-", crop, ".csv")
            if croppath == nothing
                continue
            end
            counties = readtable(croppath)
            combiner = gaussianpool
        end

        for regionid in regionindex(masterregions, :)
            if !(regionid in regionindex(counties, :, tostr=true))
                agmodels[crop][regionid] = national
                continue
            end

            county = StatisticalAgricultureModel(counties, lastindexcol, regionid)

            # Construct a pooled or fallback combination
            gdds, gddsse = combiner(national.gdds, national.gddsse, county.gdds, county.gddsse)
            kdds, kddsse = combiner(national.kdds, national.kddsse, county.kdds, county.kddsse)
            wreq, wreqse = combiner(national.wreq, national.wreqse, county.wreq, county.wreqse)
            agmodel = StatisticalAgricultureModel(county.intercept, county.interceptse, gdds, gddsse, kdds, kddsse, wreq, wreqse, county.gddoffset, county.kddoffset)
            agmodels[crop][canonicalindex(regionid)] = agmodel
        end
    end
    if config["filterstate"] == "08"
        agmodel1=deserialize(open(cachepath("1agmodels.jld"),"r"))
        agmodels["soybeans"]=agmodel1["soybeans"]
    end

    fp = open(cachepath("agmodels.jld"), "w")
    serialize(fp, agmodels)
    close(fp)
end

alluniquecrops = ["barley", "corn", "sorghum", "soybeans", "wheat", "hay"]
uniquemapping = Dict{AbstractString, Vector{AbstractString}}("barley" => ["Barley", "Barley.Winter"], "corn" => ["Maize", "maize"], "sorghum" => ["Sorghum"], "soybeans" => ["Soybeans"], "wheat" => ["Wheat", "Wheat.Winter"], "hay" => ["alfalfa", "otherhay"], "Barley" => ["barley"], "Barley.Winter" => ["barley"], "Maize" => ["maize", "corn"], "maize" => ["Maize", "corn"], "Sorghum" => ["sorghum"], "Soybeans" => ["soybeans"], "Wheat" => ["wheat"], "alfalfa" => ["hay"], "otherhay" => ["hay"])

"""
Determine which crops are not represented
"""
function missingcrops()
    for crop in alluniquecrops
        found = false
        if crop in allcrops
            found = true
        else
            for othername in uniquemapping[crop]
                if othername in allcrops
                    found = true
                    break
                end
            end
        end

        if !found
            produce(crop)
        end
    end
end

"""
Return the current crop area for every crop, in Ha
"""
function currentcroparea(crop::AbstractString)
    df = getfilteredtable(loadpath("agriculture/totalareas.csv"))
    df[:, crop] * 0.404686
end

"""
Return the current irrigation for the given crop, in mm
"""
function cropirrigationrates(crop::AbstractString)
    df = getfilteredtable(loadpath("agriculture/totalareas.csv"))
    getunivariateirrigationrates(crop)
end

"""
Read Naresh's special yield file format
"""
function read_nareshyields(crop::AbstractString, use2010yields=true)
    # Get the yield data
    if crop == "corn.co.rainfed"
        df = readtable(loadpath("colorado/blended_predicted_corn.txt"), separator=' ')
        fipses = map(xfips -> "0" * string(xfips)[2:end], names(df))
        yields = df[1:61,:]
        bayespath = loadpath("agriculture/bayesian/Corn.csv")
    elseif crop == "corn.co.irrigated"
        df = readtable(loadpath("colorado/blended_predicted_corn.txt"), separator=' ')
        fipses = map(xfips -> "0" * string(xfips)[2:end], names(df))
        yields = df[62:122,:]
        bayespath = loadpath("agriculture/bayesian/Corn.csv")
    elseif crop == "wheat.co.rainfed"
        df = readtable(loadpath("colorado/blended_predicted_wheat.txt"), separator=' ')
        fipses = map(xfips -> "0" * string(xfips)[2:end], names(df))
        yields = df[1:61,:]
        bayespath = loadpath("agriculture/bayesian/Wheat.csv")
    elseif crop == "wheat.co.irrigated"
        df = readtable(loadpath("colorado/blended_predicted_wheat.txt"), separator=' ')
        fipses = map(xfips -> "0" * string(xfips)[2:end], names(df))
        yields = df[62:122,:]
        bayespath = loadpath("agriculture/bayesian/Wheat.csv")
    end

    # Get the order into our fips
    regionindices_yield = getregionindices(fipses, false)

    if use2010yields
        # Collect coefficients to remove the trend
        coefficients = readtable(bayespath)
        timecoeffs = coefficients[coefficients[:coef] .== "time", :]

        regionindices_timecoeff = getregionindices(timecoeffs[:fips], false)
    end

    result = zeros(numcounties, numsteps)

    for ii in 1:numsteps
        orderedyields = vec(convert(Matrix{Float64}, yields[index2year(ii) - 1949, regionindices_yield]))
        if use2010yields
            # Remove the trend from the yields
            orderedyields += timecoeffs[regionindices_timecoeff, :mean] * (2010 - index2year(ii))
        end
        result[:, ii] = exp(orderedyields) # Exponentiate because in logs
    end

    result
end

"""
Read USDA QuickStats data
"""
function read_quickstats(filepath::AbstractString)
    df = readtable(filepath)
    df[:fips] = [isna.(df[ii, :County_ANSI]) ? 0 : df[ii, :State_ANSI] * 1000 + df[ii, :County_ANSI] for ii in 1:nrow(df)];
    df[:xvalue] = map(str -> parse(Float64, replace(str, ",", "")), df[:Value]);

    # Reorder these values to match regions
    indices = getregionindices(canonicalindex(convert(Vector{Int64}, df[:fips])))
    result = zeros(nrow(masterregions))
    result[indices[indices .> 0]] = df[:xvalue][indices .> 0]

    result
end

"""
Collect all crop info from one of the dictionaries, aware of name changes
"""
function crop_information(crops::Vector{Any}, dict, default; warnonmiss=false)
    [crop_information(crop, dict, default, warnonmiss=warnonmiss) for crop in crops]
end

"""
Collect single crop info from one of the dictionaries, aware of name changes
"""
function crop_information(crop::AbstractString, dict, default; warnonmiss=false)
    if crop in keys(dict)
        return dict[crop]
    else
        for othername in uniquemapping[crop]
            if othername in keys(dict)
                return dict[othername]
            end
        end
    end

    if warnonmiss
        warn("Could not find crop information for $crop.")
    end

    return default
end

include("agriculture-ers.jl")

