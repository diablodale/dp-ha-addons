#!/usr/bin/env python3

import aiohttp
import asyncio
from hass_client import HomeAssistantClient as HassClient
#from hass_client.models import Event
from hass_client.utils import async_is_supervisor
import json
import logging as standard_logging
from loguru import logger
import os
import sys

#############################
# configuration and globals
#############################

class InterceptLogHandler(standard_logging.Handler):
    """
    Redirects logging messages to Loguru.
    """
    def emit(self, record: standard_logging.LogRecord) -> None:
        # Get corresponding Loguru level if it exists
        try:
            level: str | int = logger.level(record.levelname).name
        except ValueError:
            level = record.levelno

        # Find caller from where originated the logged message
        frame, depth = standard_logging.currentframe(), 0
        while frame:
            filename = frame.f_code.co_filename
            is_logging = filename == standard_logging.__file__
            is_frozen = "importlib" in filename and "_bootstrap" in filename
            if depth > 0 and not (is_logging or is_frozen):
                break
            frame = frame.f_back
            depth += 1
        logger.opt(depth=depth, exception=record.exc_info).log(level, record.getMessage())

# Configure Loguru logger to intercept standard logging
logger.remove()
logger.add(sys.stderr, level="INFO")
standard_logging.basicConfig(handlers=[InterceptLogHandler()], level=0, force=True)

# require supervisor token
SUPERVISOR_TOKEN = os.getenv("SUPERVISOR_TOKEN")
if not SUPERVISOR_TOKEN:
  logger.error("SUPERVISOR_TOKEN is not set")
  exit(1)

# globals
WS_URL = "ws://supervisor/core/websocket"
ADDON_OPTIONS = {}

###############
# functions
###############

async def supervisor_rest_api(method: str, resource: str, post_data: dict = None, json_filter: callable = None, raw: bool = False):
    """
    Call the Home Assistant Supervisor REST api.

    Args:
        method (str): http method (GET, POST, etc.)
        resource (str): api endpoint path (/core/api/states)
        post_data (dict, optional): Data to send in POST requests
        json_filter (callable, optional): Function to filter/transform the JSON response
            (e.g. lambda x: x.get('slug'))
            This function should accept a single argument (the parsed JSON response)
            and return the desired value. The JSON passed to this function could be {}
            but it should not be None.
        raw (bool, optional): If True, return the raw response instead of parsed JSON.

    Returns:
        dict: Parsed JSON response, empty dict if no json data is returned, raw response if raw is True.

    Raises:
        Exception: If the api call fails

    Example:
        ```
        entity_states = await supervisor_rest_api("GET", "/core/api/states")
        self_slug     = (await supervisor_rest_api("GET", "/addons/self/info")).get("slug")
        self_slug     = await supervisor_rest_api("GET", "/addons/self/info", json_filter=lambda x: x.get('slug'))
        state         = await supervisor_rest_api("POST", "/core/api/states/sensor.kitchen_temperature",
                        post_data={"state": "25", "attributes": {"unit_of_measurement": "°C"}})
        ```
    """
    # Check if the method is valid
    if not hasattr(supervisor_rest_api, "valid_methods"):
        supervisor_rest_api.valid_methods = ["GET", "POST", "PUT", "DELETE"]
    if method not in supervisor_rest_api.valid_methods:
        raise ValueError(f"Invalid method: {method}. Must be one of: {supervisor_rest_api.valid_methods}")

    # Check if the resource is valid
    if not resource.startswith("/"):
        raise ValueError(f"Invalid resource: {resource}. Must start with '/'")
    if resource.endswith("/"):
        raise ValueError(f"Invalid resource: {resource}. Must not end with '/'")
    if resource == "/":
        raise ValueError("Resource cannot be '/'")

    # Check if the post_data is valid
    if post_data and method not in ["POST", "PUT"]:
        raise ValueError(f"post_data can only be used with POST or PUT methods")
    if not post_data and method in ["POST", "PUT"]:
        raise ValueError(f"post_data is required for {method} method")
    if post_data and not isinstance(post_data, dict):
        raise ValueError(f"Invalid post_data: {post_data}. Must be a dictionary")

    # Check if the json_filter is valid
    if json_filter and not callable(json_filter):
        raise ValueError(f"Invalid json_filter: {json_filter}. Must be a callable function")

    url = f"http://supervisor{resource}"
    headers = {
        "Authorization": f"Bearer {SUPERVISOR_TOKEN}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    logger.debug(f"Calling Supervisor REST api: {method} {url}")
    try:
        async with aiohttp.ClientSession() as session:
            async with session.request(
                method=method,
                url=url,
                headers=headers,
                json=post_data,
                timeout=aiohttp.ClientTimeout(total=30)
            ) as response:
                # Check if the response status is an error
                if response.status >= 400:
                    response_text = await response.text()
                    logger.error(f'api call status={response.status} txt={response_text}')
                    raise Exception(f'api call status={response.status} txt={response_text}')

                # return raw response
                if raw:
                  # If raw is True, return the raw response which could be None
                  result = await response.text()
                  logger.trace(f"api raw response: {result}")
                  return result

                # parse json response
                if response.status == 204:
                  # If 204 No Content successful response, return an empty dict
                  result = {}
                else:
                  # Parse response json into a dict
                  result = await response.json()
                  result = {} if result is None else result
                logger.trace(f"api json response: {result}")

                # check for REST error in the json result
                if result.get("result", None) == "error":
                    logger.error(f"Unexpected REST api response: {result.get("message")}")
                    raise Exception(f"Unexpected REST api response: {result.get("message")}")

                # get the data from the result
                result = result.get("data", {})

                # apply the filter if provided
                result = json_filter(result) if json_filter else result
                return result

    except aiohttp.ClientError as e:
        logger.error(f"Error calling api: {e}")
        raise

async def load_addon_options():
  """
  Load addon options from the /data/options.json file, or simulate
  it for testing purposes when static_results.json is present.
  The options are loaded into a global variable `ADDON_OPTIONS`.

  Raises:
      FileNotFoundError: If the options.json file is not found.
      json.JSONDecodeError: If the options.json file cannot be decoded.
  """
  global ADDON_OPTIONS
  try:
    with open("static_results.json", "r") as f:
      # Load the static results for testing
      logger.debug("Simulating /data/options.json")
      ADDON_OPTIONS = {
        # options having schema ? and having no value don't appear in json, their fields are missing
        # options having schema int appear in json as numbers not strings
        "accept_eula": True,
        "accept_privacy": True,
        "interval": 1,
        "server_id": 1234,
        "log_level": "debug",
        "static_results": f.read(),
      }
  except FileNotFoundError:
    # Load options.json
    try:
      with open("/data/options.json", "r") as f:
        ADDON_OPTIONS = json.load(f)
    except FileNotFoundError:
      logger.error("options.json file not found")
      raise
    except json.JSONDecodeError:
      logger.error("Failed to decode options.json")
      raise
  logger.trace(f"Loaded addon options: {ADDON_OPTIONS}")


def enforce_eula_privacy_accept():
    """
    Check if the EULA and privacy policy have been accepted.
    If not, raise an exception.

    Testing shows that EULA and Privacy Policy acceptance are recorded
    in `/root/.config/ookla/speedtest-cli.json`
    ```json
    { "Settings": {
        "LicenseAccepted": "604ec27f828456331ebf441826292c49276bd3c1bee1a2f65a6452f505c4061c",
        "GDPRTimeStamp": 1743729654
    } }
    ```
    where
    - `LicenseAccepted` is recorded when EULA accepted; set to a SHA256 hash
    - `GDPRTimeStamp` is recorded when Privacy Policy accepted; set to current epoch timestamp
    and both, one, or none of these values may be present in the file.
    Any previous state of the file is retained and not overwritten when already valid.
    Using `speedtest --accept-license --accept-gdpr` will record any missing user acceptance.
    Therefore, it is unneeded to backup/restore the file with /data.

    Raises:
        Exception: If the EULA or privacy policy has not been accepted.
    """
    if not ADDON_OPTIONS.get("accept_eula", False) or not ADDON_OPTIONS.get("accept_privacy", False):
        logger.critical("Ookla requires you to accept their EULA and Privacy Policy.")
        logger.critical("Please accept the EULA and Privacy Policy in the addon config UI.")
        raise Exception("Ookla EULA or Privacy Policy not accepted")

###############
# main
###############

async def main():
  # Check if running in a supervisor environment
  if not await async_is_supervisor():
    logger.error("This script can only run within an addon having supervisor access")
    return 1

  # validate addon options
  await load_addon_options()
  enforce_eula_privacy_accept()

  # Initialize Hass client
  async with HassClient(websocket_url=WS_URL, token=SUPERVISOR_TOKEN) as client:
    try:
      logger.info("Do work with Home Assistant")
      #await client.subscribe_events(lambda event: logger.debug(f"Event received: {event}"), event_type="state_changed")
      #await asyncio.sleep(10)
      devices = await client.get_device_registry()
      logger.info(f"Devices: {devices}")

      # BUGBUG https://github.com/music-assistant/python-hass-client/issues/234
      logger.debug("workaround race condition bug in https://github.com/music-assistant/python-hass-client/issues/234")
      await asyncio.sleep(0.5)

    finally:
      logger.debug("Finished work with Home Assistant")

  logger.trace("Done with main()")

if __name__ == "__main__":
  asyncio.run(main(), debug=True)
