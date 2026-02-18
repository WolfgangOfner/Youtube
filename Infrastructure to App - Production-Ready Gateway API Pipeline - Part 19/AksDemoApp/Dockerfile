# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

# This stage is used when running from VS in fast mode (Default for Debug configuration)
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
USER $APP_UID
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["AksDemoApp/AksDemoApp.csproj", "AksDemoApp/"]
COPY ["AksDemoApp.Test/AksDemoApp.Test.csproj", "AksDemoApp.Test/"]

RUN dotnet restore "AksDemoApp/AksDemoApp.csproj"
RUN dotnet restore "AksDemoApp.Test/AksDemoApp.Test.csproj"
COPY . .

WORKDIR "/src"
RUN dotnet build "AksDemoApp/AksDemoApp.csproj" -c $BUILD_CONFIGURATION -o /app/build
RUN dotnet build "AksDemoApp.Test/AksDemoApp.Test.csproj" -c $BUILD_CONFIGURATION --no-restore

FROM build AS test  
ARG BuildId=localhost
LABEL test=${BuildId}
RUN dotnet test --no-build -c Release --results-directory /testresults --logger "trx;LogFileName=test_results.trx" /p:CollectCoverage=true /p:CoverletOutputFormat=json%2cCobertura /p:CoverletOutput=/testresults/coverage/ -p:MergeWith=/testresults/coverage/coverage.json  AksDemoApp.Test/AksDemoApp.Test.csproj  

FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "AksDemoApp/AksDemoApp.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "AksDemoApp.dll"]

#FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
#USER $APP_UID
#WORKDIR /app
#EXPOSE 8080
#EXPOSE 8081

#FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
#ARG BUILD_CONFIGURATION=Release
#WORKDIR /src
#COPY ["AksDemoApp/AksDemoApp.csproj", "AksDemoApp/"]
#COPY ["AksDemoApp.Test/AksDemoApp.Test.csproj", "AksDemoApp.Test/"]
#
#RUN dotnet restore "AksDemoApp/AksDemoApp.csproj"
#RUN dotnet restore "AksDemoApp.Test/AksDemoApp.Test.csproj"
#COPY . .
#
#RUN dotnet build "AksDemoApp/AksDemoApp.csproj" -c $BUILD_CONFIGURATION -o /app/build --no-restore
#RUN dotnet build "AksDemoApp.Test/AksDemoApp.Test.csproj" -c $BUILD_CONFIGURATION --no-restore
#
#FROM build AS test  
#ARG BuildId=localhost
#LABEL test=${BuildId}
#RUN dotnet test --no-build -c Release --results-directory /testresults --logger "trx;LogFileName=test_results.trx" /p:CollectCoverage=true /p:CoverletOutputFormat=json%2cCobertura /p:CoverletOutput=/testresults/coverage/ -p:MergeWith=/testresults/coverage/coverage.json  AksDemoApp.Test/AksDemoApp.Test.csproj  
#
#FROM build AS publish
#ARG BUILD_CONFIGURATION=Release
#RUN dotnet publish "AksDemoApp/AksDemoApp.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false
#
#FROM base AS final
#WORKDIR /app
#COPY --from=publish /app/publish .
#ENTRYPOINT ["dotnet", "AksDemoApp.dll"]