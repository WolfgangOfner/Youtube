var builder = DistributedApplication.CreateBuilder(args);

var apiService = builder.AddProject<Projects.DefenderForDevOpsDemo_ApiService>("apiservice");

builder.AddProject<Projects.DefenderForDevOpsDemo_Web>("webfrontend")
    .WithExternalHttpEndpoints()
    .WithReference(apiService)
    .WaitFor(apiService);

builder.Build().Run();
