using Test
using Statistics
using Distributions
using BayesianINT
using BayesianINT.OneTimescale
using BayesianINT.Models

@testset "OneTimescale Model Tests" begin
    # Setup test data and model
    test_prior = [Uniform(0.1, 10.0)]  # tau prior
    dt = 0.01
    T = 100.0
    num_trials = 10
    n_lags = 3000
    ntime = Int(T / dt)
    test_data = randn(num_trials, ntime)  # 10 trials, 10000 timepoints
    data_var = std(test_data)
    data_sum_stats = mean(comp_ac_fft(test_data; n_lags=n_lags), dims=1)[:]
    
    model = OneTimescaleModel(
        test_data,           # data
        test_prior,         # prior
        data_sum_stats,     # data_sum_stats
        0.1,                # epsilon
        dt,                 # dt
        T,                  # T
        num_trials,         # numTrials
        data_var,           # data_var
        n_lags              # n_lags
    )

    @testset "Model Construction" begin
        @test model isa OneTimescaleModel
        @test model isa AbstractTimescaleModel
        @test size(model.data) == (num_trials, ntime)
        @test length(model.prior) == 1  # single tau parameter
        @test model.prior[1] isa Uniform
    end

    @testset "Informed Prior Construction" begin
        informed_model = OneTimescaleModel(
            test_data,
            "informed",
            data_sum_stats,
            0.1,
            dt,
            T,
            num_trials,
            data_var,
            n_lags
        )
        @test informed_model.prior[1] isa Normal
    end

    @testset "generate_data" begin
        theta = [1.0]  # test parameter (tau)
        simulated_data = Models.generate_data(model, theta)
        
        @test size(simulated_data) == (model.numTrials, Int(model.T/model.dt))
        @test !any(isnan, simulated_data)
        @test !any(isinf, simulated_data)
        
        # Test statistical properties
        @test abs(std(simulated_data) - sqrt(model.data_var)) < 0.1
        @test abs(mean(simulated_data)) < 0.1  # Should be close to zero
    end

    @testset "summary_stats" begin
        theta = [1.0]
        simulated_data = Models.generate_data(model, theta)
        
        stats = Models.summary_stats(model, simulated_data)
        
        @test length(stats) == model.n_lags
        @test !any(isnan, stats)
        @test stats[1] ≈ 1.0 atol=0.1  # First lag should be close to 1
        @test all(abs.(stats) .<= 1.0)  # All autocorrelations should be ≤ 1
    end

    @testset "distance_function" begin
        theta1 = [1.0]
        theta2 = [2.0]
        
        data1 = Models.generate_data(model, theta1)
        data2 = Models.generate_data(model, theta2)
        
        stats1 = Models.summary_stats(model, data1)
        stats2 = Models.summary_stats(model, data2)
        
        distance = Models.distance_function(model, stats1, stats2)
        
        @test distance isa Float64
        @test distance >= 0.0
        @test Models.distance_function(model, stats1, stats1) ≈ 0.0 atol=1e-10
        
        # Test that different parameters lead to different distances
        @test distance > Models.distance_function(model, stats1, stats1)
    end

    @testset "Model Behavior" begin
        # Test effect of different timescales
        theta1 = [0.5]  # faster timescale
        theta2 = [2.0]  # slower timescale
        
        data1 = Models.generate_data(model, theta1)
        data2 = Models.generate_data(model, theta2)
        
        ac1 = Models.summary_stats(model, data1)
        ac2 = Models.summary_stats(model, data2)
        
        # Test that slower timescale has higher autocorrelation at longer lags
        lag_idx = 100  # Compare at lag 100
        @test ac2[lag_idx] > ac1[lag_idx]
    end
end
