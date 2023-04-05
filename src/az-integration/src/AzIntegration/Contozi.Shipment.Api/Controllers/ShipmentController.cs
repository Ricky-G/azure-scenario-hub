using Contozi.Shipment.API.Models;
using Microsoft.AspNetCore.Mvc;

namespace Contozi.Shipment.API.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class ShipmentsController : ControllerBase
    {
        [HttpGet]
        public ActionResult<IEnumerable<ShipmentModel>> GetShipments()
        {

            // Implement logic to retrieve a list of shipments
            throw new NotImplementedException();
        }

        [HttpPost]
        public ActionResult<ShipmentModel> CreateShipment([FromBody] ShipmentModel shipment)
        {
            // Implement logic to create a new shipment
            throw new NotImplementedException();
        }

        [HttpGet("{shipmentId}")]
        public ActionResult<ShipmentModel> GetShipmentById(string shipmentId)
        {
            // Implement logic to retrieve a specific shipment by ID
            throw new NotImplementedException();
        }

        [HttpPut("{shipmentId}")]
        public ActionResult<ShipmentModel> UpdateShipment(string shipmentId, [FromBody] ShipmentModel shipment)
        {
            // Implement logic to update a shipment by ID
            throw new NotImplementedException();
        }

        [HttpDelete("{shipmentId}")]
        public IActionResult DeleteShipment(string shipmentId)
        {
            // Implement logic to delete a shipment by ID
            throw new NotImplementedException();
        }
    }
}