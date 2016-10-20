using AdaptiveIS, Base.Test

f(x)=mean(x)>=0.85 ? 1. : 0.
srand(5)
sim=ais(f,3,t0=[1;0;1],accel="saa")

@test_approx_eq_eps sim.μ[end] 0.0151874 1e-3

@test_approx_eq_eps sim.θ[end,:] [1.37287, 0.436164, 1.37691] 1e-2

@test_approx_eq sim.λ [1.5; 0.5; 1.5]
