import prometheus_client
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator, metrics  # type: ignore


def mount_on(app: FastAPI):
    Instrumentator().instrument(app).expose(app)

    instrumentator = Instrumentator(
        should_group_status_codes=False,
        should_ignore_untemplated=True,
        should_respect_env_var=True,
        should_instrument_requests_inprogress=True,
        excluded_handlers=[".*admin.*", "/metrics"],
        env_var_name="ENABLE_METRICS",
        inprogress_name="inprogress",
        inprogress_labels=True,
    )

    instrumentator.expose(app, include_in_schema=False)


def merge_instruments():
    prometheus_summary_fetch_full = []
    prometheus_summary_fetch_partial = []
    prometheus_summary_merge = []
    prometheus_summary_build = []
    for z in range(0, 14 + 1):
        prometheus_summary_fetch_full.append(
            prometheus_client.Summary(f"fetch_full_z{z}", f"Zoom {z} fetch full tile")
        )
        prometheus_summary_fetch_partial.append(
            prometheus_client.Summary(
                f"fetch_partial_z{z}", f"Zoom {z} fetch partial tile"
            )
        )
        prometheus_summary_merge.append(
            prometheus_client.Summary(f"merge_z{z}", f"Zoom {z} merge")
        )
        prometheus_summary_build.append(
            prometheus_client.Summary(f"build_z{z}", f"Zoom {z} build")
        )

    return [
        prometheus_summary_fetch_full,
        prometheus_summary_fetch_partial,
        prometheus_summary_merge,
        prometheus_summary_build,
    ]
