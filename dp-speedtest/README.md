# dp Speedtest

_Measure internet connection performance metrics with Speedtest CLI_

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armhf Architecture][armhf-shield]
![Supports armv7 Architecture][armv7-shield]
![Supports i386 Architecture][i386-shield]

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armhf-shield]: https://img.shields.io/badge/armhf-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg
[i386-shield]: https://img.shields.io/badge/i386-yes-green.svg

## License recording

Ookla requires you to accept their EULA and privacy policy before using the speedtest CLI.
It is possible to accept both, one, or none of them.
It records your acceptance in a file located at `/root/.config/ookla/speedtest-cli.json`.

### Sample 1

```
{
    "Settings": {
        "LicenseAccepted": "604ec27f828456331ebf441826292c49276bd3c1bee1a2f65a6452f505c4061c",
        "GDPRTimeStamp": 1743729654
    }
}
```

- `LicenseAccepted` is recorded when EULA accepted; set to a SHA256 hash
- `GDPRTimeStamp` is recorded when Privacy Policy accepted; set to current epoch timestamp

### Sample 2

Taken by restoring sample 1 then running with both `--accept-license` and `--accept-gdpr` options.
Since neither field values changed, the file is not updated if already valid for given options.

```
{
    "Settings": {
        "LicenseAccepted": "604ec27f828456331ebf441826292c49276bd3c1bee1a2f65a6452f505c4061c",
        "GDPRTimeStamp": 1743729654
    }
}
```

### prompt to accept EULA and privacy

```
079c05d38ba7:/# su -c 'speedtest --selection-details'
==============================================================================

You may only use this Speedtest software and information generated
from it for personal, non-commercial use, through a command line
interface on a personal computer. Your use of this software is subject
to the End User License Agreement, Terms of Use and Privacy Policy at
these URLs:

  https://www.speedtest.net/about/eula
  https://www.speedtest.net/about/terms
  https://www.speedtest.net/about/privacy

==============================================================================

Do you accept the license? [type YES to accept]: yes
License acceptance recorded. Continuing.

==============================================================================

Ookla collects certain data through Speedtest that may be considered
personally identifiable, such as your IP address, unique device
identifiers or location. Ookla believes it has a legitimate interest
to share this data with internet providers, hardware manufacturers and
industry regulators to help them understand and create a better and
faster internet. For further information including how the data may be
shared, where the data may be transferred and Ookla's contact details,
please see our Privacy Policy at:

       http://www.speedtest.net/privacy

==============================================================================

Do you accept the license? [type YES to accept]:
```

### auto accept EULA and privacy

```
079c05d38ba7:/# su -c 'speedtest --accept-license --accept-gdpr'
==============================================================================

You may only use this Speedtest software and information generated
from it for personal, non-commercial use, through a command line
interface on a personal computer. Your use of this software is subject
to the End User License Agreement, Terms of Use and Privacy Policy at
these URLs:

  https://www.speedtest.net/about/eula
  https://www.speedtest.net/about/terms
  https://www.speedtest.net/about/privacy

==============================================================================

License acceptance recorded. Continuing.

==============================================================================

Ookla collects certain data through Speedtest that may be considered
personally identifiable, such as your IP address, unique device
identifiers or location. Ookla believes it has a legitimate interest
to share this data with internet providers, hardware manufacturers and
industry regulators to help them understand and create a better and
faster internet. For further information including how the data may be
shared, where the data may be transferred and Ookla's contact details,
please see our Privacy Policy at:

       http://www.speedtest.net/privacy

==============================================================================

License acceptance recorded. Continuing.


   Speedtest by Ookla

      Server: 1&1 Mobilfunk - Berlin (id: 64700)
         ISP: 1&1 Versatel
Idle Latency:     9.03 ms   (jitter: 0.57ms, low: 8.52ms, high: 9.29ms)
    Download:   116.72 Mbps (data used: 168.0 MB)
                 45.92 ms   (jitter: 10.80ms, low: 11.92ms, high: 85.84ms)
      Upload:    38.17 Mbps (data used: 18.6 MB)
                156.03 ms   (jitter: 6.32ms, low: 24.29ms, high: 172.51ms)
 Packet Loss:     0.0%
  Result URL: https://www.speedtest.net/result/c/35ee77e5-7f51-463c-88c0-1674cbe0564a
079c05d38ba7:/#
```

### auto accept 2

With `su -c 'speedtest --accept-license --accept-gdpr -v --format=json --progress=no > /data/speedtest-results.json'`

```
==============================================================================

You may only use this Speedtest software and information generated
from it for personal, non-commercial use, through a command line
interface on a personal computer. Your use of this software is subject
to the End User License Agreement, Terms of Use and Privacy Policy at
these URLs:

  https://www.speedtest.net/about/eula
  https://www.speedtest.net/about/terms
  https://www.speedtest.net/about/privacy

==============================================================================

License acceptance recorded. Continuing.

==============================================================================

Ookla collects certain data through Speedtest that may be considered
personally identifiable, such as your IP address, unique device
identifiers or location. Ookla believes it has a legitimate interest
to share this data with internet providers, hardware manufacturers and
industry regulators to help them understand and create a better and
faster internet. For further information including how the data may be
shared, where the data may be transferred and Ookla's contact details,
please see our Privacy Policy at:

       http://www.speedtest.net/privacy

==============================================================================

License acceptance recorded. Continuing.

{"type":"log","timestamp":"2025-04-04T03:14:35Z","message":"Loaded latency: cannot read response.: [0] Cannot read from uninitialized socket.","level":"warning"}
{"type":"log","timestamp":"2025-04-04T03:14:39Z","message":"No libz support available, not compressing data.","level":"warning"}
```
