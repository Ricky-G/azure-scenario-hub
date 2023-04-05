namespace Contozi.Shipment.API.Models
{
    public class ShipmentModel
    {
        public string ShipmentId { get; set; }
        public string Origin { get; set; }
        public string Destination { get; set; }
        public string Status { get; set; }
        public DateTime PickupDate { get; set; }
        public DateTime DeliveryDate { get; set; }
        public double Weight { get; set; }
        public double Volume { get; set; }
    }
}
