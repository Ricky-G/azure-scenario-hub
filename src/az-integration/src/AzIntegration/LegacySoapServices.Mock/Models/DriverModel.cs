using System.Runtime.Serialization;

namespace LegacySoapServices.Mock.Models
{
    [DataContract]
    public class DriverModel
    {
        [DataMember]
        public string DriverId { get; set; }

        [DataMember]
        public string FirstName { get; set; }
        
        [DataMember]
        public string LastName { get; set; }

        [DataMember]
        public DateTime DateOfBirth { get; set; }

        [DataMember]
        public string LicenseNumber { get; set; }

        [DataMember]
        public string PhoneNumber { get; set; }
        
        [DataMember]
        public string Email { get; set; }
    }
}
