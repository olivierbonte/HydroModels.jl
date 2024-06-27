@reexport module SIMHYD
# https://github.com/hydrogo/LHMP/blob/master/models/simhyd_cemaneige.py
using ..LumpedHydro
using ..LumpedHydro.Symbolics: @variables
using ..LumpedHydro.ModelingToolkit: @parameters
using ..LumpedHydro.ModelingToolkit: t_nounits as t
using ..LumpedHydro.ModelingToolkit: Num
"""
elements in SIMHYD
"""
function SIMHYD_ELE(; name::Symbol, mtk::Bool=true)
    @variables prcp(t) = 0.0
    @variables pet(t) = 0.0

    @variables U(t) = 0.0
    @variables IMAX(t) = 0.0
    @variables INT(t) = 0.0
    @variables INR(t) = 0.0
    @variables RMO(t) = 0.0
    @variables IRUN(t) = 0.0
    @variables EVAP(t) = 0.0
    @variables SRUN(t) = 0.0
    @variables REC(t) = 0.0
    @variables SMF(t) = 0.0
    @variables POT(t) = 0.0
    @variables BAS(t) = 0.0
    @variables GWF(t) = 0.0
    @variables SMS(t) = 0.0
    @variables GW(t) = 0.0

    @parameters INSC = 0.0
    @parameters COEFF = 0.0
    @parameters SQ = 0.0
    @parameters SMSC = 0.0
    @parameters SUB = 0.0
    @parameters CRAK = 0.0
    @parameters K = 0.0
    @parameters etmul = 0.0
    @parameters DELAY = 0.0
    @parameters X_m = 0.0

    funcs = [
        SimpleFlux([pet] => [IMAX], [INSC], flux_exprs=@.[min(INSC, pet)]),
        SimpleFlux([prcp, IMAX] => [INT], Num[], flux_exprs=@.[min(IMAX, prcp)]),
        SimpleFlux([prcp, INT] => [INR], Num[], flux_exprs=@.[prcp - INT]),
        SimpleFlux([pet, INT] => [POT], Num[], flux_exprs=@.[pet - INT]),
        SimpleFlux([POT, SMS] => [EVAP], [SMSC], flux_exprs=@.[min(10 * (SMS / SMSC), POT)]),
        SimpleFlux([INR, SMS] => [RMO], [COEFF, SQ, SMSC], flux_exprs=@.[min(COEFF * exp(-SQ * (SMS / SMSC)), INR)]),
        SimpleFlux([INR, RMO] => [IRUN], Num[], flux_exprs=@.[INR - RMO]),
        SimpleFlux([RMO, SMS] => [SRUN], [SUB, SMSC], flux_exprs=@.[SUB * (SMS / SMSC) * RMO]),
        SimpleFlux([RMO, SRUN, SMS] => [REC], [CRAK, SMSC], flux_exprs=@.[CRAK * (SMS / SMSC) * (RMO - SRUN)]),
        SimpleFlux([RMO, SRUN, REC] => [SMF], Num[], flux_exprs=@.[RMO - SRUN - REC]),
        SimpleFlux([SMS, SMF] => [GWF], [SMSC], flux_exprs=@.[ifelse(SMS == SMSC, SMF, 0.0)]),
        SimpleFlux([GW] => [BAS], [K], flux_exprs=@.[K * GW]),
        SimpleFlux([IRUN, SRUN, BAS] => [U], [K], flux_exprs=@.[IRUN + SRUN + BAS]),
    ]

    dfuncs = [
        StateFlux([SMF] => [EVAP, GWF], SMS, funcs=funcs),
        StateFlux([REC, GWF] => [BAS], GW, funcs=funcs)
    ]

    HydroElement(
        Symbol(name, :_soil_),
        funcs=funcs,
        dfuncs=dfuncs,
        mtk=mtk,
    )
end

function Unit(; name::Symbol, mtk::Bool=true)
    elements = [
        SIMHYD_ELE(name=name, mtk=mtk),
    ]

    HydroUnit(
        name,
        elements=elements,
    )
end
end