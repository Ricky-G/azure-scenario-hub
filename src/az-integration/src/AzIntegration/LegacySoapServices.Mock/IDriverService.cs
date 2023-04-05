using LegacySoapServices.Mock.Models;
using System.ServiceModel;

namespace LegacySoapServices.Mock
{
    [ServiceContract]
    public interface IDriverService
    {
        [OperationContract]
        Task<List<DriverModel>> GetDrivers();

        [OperationContract]
        Task<DriverModel> CreateDriver(DriverModel driver);

        [OperationContract]
        Task<DriverModel> GetDriverById(string id);

        [OperationContract]
        Task<DriverModel> UpdateDriver(string id, DriverModel driver);

        [OperationContract]
        Task DeleteDriver(string id);
    }
}
