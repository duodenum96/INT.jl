using Test
using Statistics
using Distributions
using BayesianINT
using BayesianINT.OrnsteinUhlenbeck
using BayesianINT.OneTimescaleAndOsc
using BayesianINT.Models

@testset "OneTimescaleAndOsc Model Tests" begin
    # Setup test data and model parameters
    dt = 0.01
    T = 100.0
    num_trials = 10
    ntime = Int(T / dt)
    
    # Generate test data with known parameters
    true_tau = 1.0
    true_freq = 0.1  # Hz
    true_coeff = 0.5
    test_data = generate_ou_with_oscillation(
        [true_tau, true_freq, true_coeff],
        dt, T, num_trials, 0.0, 1.0
    )
    
    # Compute PSD for the test data
    data_psd, freqs = comp_psd(test_data, 1/dt)
    data_mean = mean(test_data)
    data_var = var(test_data)

    data_psd = mean(data_psd, dims=1)[:]

    # Define test priors
    test_prior = [
        Uniform(0.1, 10.0),  # tau prior
        Uniform(0.01, 1.0),  # frequency prior
        Uniform(0.0, 1.0)    # amplitude prior
    ]

    model = OneTimescaleAndOscModel(
        test_data,           # data
        test_prior,         # prior
        (data_psd, freqs),  # data_sum_stats
        0.1,                # epsilon
        dt,                 # dt
        T,                  # T
        num_trials,         # numTrials
        data_mean,          # data_mean
        data_var            # data_var
    )

    @testset "Model Construction" begin
        @test model isa OneTimescaleAndOscModel
        @test model isa AbstractTimescaleModel
        @test size(model.data) == (num_trials, ntime)
        @test length(model.prior) == 3  # tau, frequency, amplitude
        @test all(p isa Uniform for p in model.prior)
    end

    @testset "Informed Prior Construction" begin
        informed_model = OneTimescaleAndOscModel(
            test_data,
            "informed",
            (data_psd, freqs),
            0.1,
            dt,
            T,
            num_trials,
            data_mean,
            data_var
        )
        @test informed_model.prior[1] isa Normal  # tau prior
        @test informed_model.prior[2] isa Normal  # frequency prior
        @test informed_model.prior[3] isa Uniform # amplitude prior
    end

    @testset "generate_data" begin
        theta = [1.0, 0.1, 0.5]  # test parameters (tau, freq, amplitude)
        simulated_data = Models.generate_data(model, theta)
        
        @test size(simulated_data) == (model.numTrials, Int(model.T/model.dt))
        @test !any(isnan, simulated_data)
        @test !any(isinf, simulated_data)
        
        # Test statistical properties
        @test abs(mean(simulated_data) - model.data_mean) < 0.1
        @test abs(std(simulated_data) - sqrt(model.data_var)) < 0.1
    end

    @testset "summary_stats" begin
        theta = [1.0, 0.1, 0.5]
        simulated_data = Models.generate_data(model, theta)
        
        stats = Models.summary_stats(model, simulated_data)
        
        @test length(stats) == 2  # Should return (psd, freqs)
        @test !any(isnan, stats[1])  # PSD should not contain NaNs
        @test !any(isnan, stats[2])  # Frequencies should not contain NaNs
        @test length(stats[1]) == length(stats[2])  # PSD and freq vectors should match
    end

    @testset "distance_function" begin
        theta1 = [1.0, 0.1, 0.5]
        theta2 = [2.0, 0.2, 0.7]
        
        data1 = Models.generate_data(model, theta1)
        data2 = Models.generate_data(model, theta2)
        
        stats1 = Models.summary_stats(model, data1)
        stats2 = Models.summary_stats(model, data2)
        
        distance = Models.distance_function(model, stats1, stats2)
        
        @test distance isa Float64
        @test distance >= 0.0
    end

    @testset "Model Behavior" begin
        # Test effect of different parameters
        theta_base = [1.0, 0.1, 0.5]
        theta_higher_freq = [1.0, 0.2, 0.5]
        
        data_base = Models.generate_data(model, theta_base)
        data_higher_freq = Models.generate_data(model, theta_higher_freq)
        
        psd_base = Models.summary_stats(model, data_base)[1]
        psd_higher_freq = Models.summary_stats(model, data_higher_freq)[1]
        freqs = Models.summary_stats(model, data_base)[2]
        
        # Find peak frequencies
        peak_freq_base = freqs[argmax(psd_base)]
        peak_freq_higher = freqs[argmax(psd_higher_freq)]
        
        # Test that higher frequency parameter leads to higher peak frequency
        @test peak_freq_higher > peak_freq_base
    end
end
