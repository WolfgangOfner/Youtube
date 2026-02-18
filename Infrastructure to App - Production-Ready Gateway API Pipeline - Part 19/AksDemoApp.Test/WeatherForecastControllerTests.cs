using AksDemoApp.Controllers;

namespace AksDemoApp.Test
{
    public class WeatherForecastControllerTests
    {
        [Fact]
        public void Get_ReturnsWeatherForecasts()
        {
            // Arrange
            var controller = new WeatherForecastController();

            // Act
            var result = controller.Get();

            // Assert
            Assert.NotNull(result);
            var forecasts = result.ToList();
            Assert.Equal(5, forecasts.Count);
        }

        [Fact]
        public void Get_ReturnsCorrectNumberOfForecasts()
        {
            // Arrange
            var controller = new WeatherForecastController();

            // Act
            var result = controller.Get().ToList();

            // Assert
            Assert.Equal(5, result.Count);
        }

        [Fact]
        public void Get_EachForecastHasValidDate()
        {
            // Arrange
            var controller = new WeatherForecastController();

            // Act
            var result = controller.Get();

            // Assert
            foreach (var forecast in result)
            {
                Assert.True(forecast.Date > DateOnly.FromDateTime(DateTime.Now));
            }
        }

        [Fact]
        public void Get_EachForecastHasValidTemperature()
        {
            // Arrange
            var controller = new WeatherForecastController();

            // Act
            var result = controller.Get();

            // Assert
            foreach (var forecast in result)
            {
                Assert.InRange(forecast.TemperatureC, -20, 54);
            }
        }

        [Fact]
        public void Get_EachForecastHasSummary()
        {
            // Arrange
            var controller = new WeatherForecastController();

            // Act
            var result = controller.Get();

            // Assert
            foreach (var forecast in result)
            {
                Assert.NotNull(forecast.Summary);
                Assert.NotEmpty(forecast.Summary);
            }
        }

        [Fact]
        public void Get_ReturnsDifferentForecastsOnMultipleCalls()
        {
            // Arrange
            var controller = new WeatherForecastController();

            // Act
            var firstCall = controller.Get().ToList();
            var secondCall = controller.Get().ToList();

            // Assert
            bool hasDifference = false;
            for (int i = 0; i < firstCall.Count; i++)
            {
                if (firstCall[i].TemperatureC != secondCall[i].TemperatureC ||
                    firstCall[i].Summary != secondCall[i].Summary)
                {
                    hasDifference = true;
                    break;
                }
            }
            Assert.True(hasDifference);
        }
    }

    public class WeatherForecastTests
    {
        [Fact]
        public void TemperatureF_CalculatesCorrectly_ForZeroCelsius()
        {
            // Arrange
            var forecast = new WeatherForecast
            {
                TemperatureC = 0
            };

            // Act
            var temperatureF = forecast.TemperatureF;

            // Assert
            Assert.Equal(32, temperatureF);
        }

        [Fact]
        public void TemperatureF_CalculatesCorrectly_ForPositiveTemperature()
        {
            // Arrange
            var forecast = new WeatherForecast
            {
                TemperatureC = 20
            };

            // Act
            var temperatureF = forecast.TemperatureF;

            // Assert
            Assert.InRange(temperatureF, 67, 69);
        }

        [Fact]
        public void TemperatureF_CalculatesCorrectly_ForNegativeTemperature()
        {
            // Arrange
            var forecast = new WeatherForecast
            {
                TemperatureC = -10
            };

            // Act
            var temperatureF = forecast.TemperatureF;

            // Assert
            Assert.InRange(temperatureF, 13, 15);
        }

        [Fact]
        public void WeatherForecast_CanSetAllProperties()
        {
            // Arrange & Act
            var forecast = new WeatherForecast
            {
                Date = DateOnly.FromDateTime(DateTime.Now),
                TemperatureC = 25,
                Summary = "Warm"
            };

            // Assert
            Assert.NotEqual(default(DateOnly), forecast.Date);
            Assert.Equal(25, forecast.TemperatureC);
            Assert.Equal("Warm", forecast.Summary);
        }

        [Theory]
        [InlineData(-20, -4)]
        [InlineData(0, 32)]
        [InlineData(10, 50)]
        [InlineData(20, 68)]
        [InlineData(30, 86)]
        [InlineData(40, 104)]
        public void TemperatureF_ConvertsCorrectly(int celsius, int expectedFahrenheit)
        {
            // Arrange
            var forecast = new WeatherForecast
            {
                TemperatureC = celsius
            };

            // Act
            var actualFahrenheit = forecast.TemperatureF;

            // Assert
            Assert.InRange(actualFahrenheit, expectedFahrenheit - 1, expectedFahrenheit + 1);
        }
    }
}
