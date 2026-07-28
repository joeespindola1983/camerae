# Offline star catalog

`gaia_dr3_bright_stars.camcat` is generated from the public Gaia DR3
`gaiadr3.gaia_source` table hosted by the ESA Gaia Archive.

Query date: 2026-07-27

Selection: the 20,000 brightest rows with `phot_g_mean_mag <= 7`, ordered by
`phot_g_mean_mag`, retaining `source_id`, `ra`, `dec`, and
`phot_g_mean_mag`.

Source: https://gea.esac.esa.int/archive/
