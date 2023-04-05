using System.Runtime.Serialization;

namespace Contozi.Shipment.API.Models
{
    [DataContract]
    public class ShipmentModel
    {
        [DataMember]
        public string ShipmentId { get; set; }
        [DataMember]
        public string Origin { get; set; }
        [DataMember]
        public string Destination { get; set; }
        [DataMember]
        public string Status { get; set; }
        [DataMember]
        public DateTime PickupDate { get; set; }
        [DataMember]
        public DateTime DeliveryDate { get; set; }
        [DataMember]
        public double Weight { get; set; }
        [DataMember]
        public double Volume { get; set; }
    }
}
