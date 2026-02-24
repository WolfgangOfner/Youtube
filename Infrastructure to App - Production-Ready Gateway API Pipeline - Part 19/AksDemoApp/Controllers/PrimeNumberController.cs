//using Microsoft.AspNetCore.Mvc;
//
//namespace AksDemoApp.Controllers
//{
//    [ApiController]
//    [Route("[controller]")]
//    public class PrimeNumberController : ControllerBase
//    {
//        [HttpGet]
//        public long Index(int nThPrimeNumber)
//        {
//            var count = 0;
//            long a = 2;
//
//            while (count < nThPrimeNumber)
//            {
//                long b = 2;
//                var prime = 1;
//
//                while (b * b <= a)
//                {
//                    if (a % b == 0)
//                    {
//                        prime = 0;
//
//                        break;
//                    }
//
//                    b++;
//                }
//
//                if (prime > 0)
//                {
//                    count++;
//                }
//
//                a++;
//            }
//
//            return --a;
//        }
//    }
//}
