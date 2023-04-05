using Contozi.Driver.Api.Models;
using Microsoft.AspNetCore.Mvc;

namespace Contozi.Driver.Api.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class DriversController : ControllerBase
    {
        [HttpGet]
        public ActionResult<List<DriverModel>> GetDrivers()
        {
            // Implement the logic to retrieve a list of drivers
            return Ok();
        }

        [HttpPost]
        public ActionResult<DriverModel> CreateDriver([FromBody] DriverModel driver)
        {
            // Implement the logic to create a new driver
            return CreatedAtAction(nameof(GetDriverById), new { driverId = driver.DriverId }, driver);
        }

        [HttpGet("{driverId}")]
        public ActionResult<DriverModel> GetDriverById(string driverId)
        {
            // Implement the logic to retrieve a specific driver by ID
            return Ok();
        }

        [HttpPut("{driverId}")]
        public ActionResult<DriverModel> UpdateDriver(string driverId, [FromBody] DriverModel driver)
        {
            // Implement the logic to update a driver by ID
            return Ok(driver);
        }

        [HttpDelete("{driverId}")]
        public IActionResult DeleteDriver(string driverId)
        {
            // Implement the logic to delete a driver by ID
            return NoContent();
        }
    }
}