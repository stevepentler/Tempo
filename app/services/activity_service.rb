class ActivityService
  include Formatter
  include Scoring
  attr_reader :client,
              :race,
              :current_user

  def initialize(current_user, race=nil)
    @client = Strava::Api::V3::Client.new(:access_token => "#{current_user.token}")
    @race = race ||= Race.first
    @current_user = current_user
  end

  def list_athlete_activities
    Rails.cache.fetch("workouts-index-#{current_user.id}", expires_in: (0.2).hours) do 
      client.list_athlete_activities.select {|activity| workout_specifications(activity) }
    end
  end

  def workout_specifications(activity)
    (activity["type"] == "Run" && activity["max_speed"] != 0.0) 
  end

  def count_activity_services
    list_athlete_activities.count
  end

  def single_activity(id)
    client.retrieve_an_activity(id)
  end

  def activity_id(activity)
    activity["id"]
  end

  def name(activity)
    activity["name"]
  end

  def type(activity)
    activity["type"]
  end

  def start_date(activity)
    format_date(activity)
  end

  def start_time(activity)
    activity["start_date_local"].split("T").last.chop
  end 

  def distance(activity)
    meters = activity["distance"] 
    miles = (meters * meter_to_mile).round(2)
  end

  def duration(activity)
    total_seconds = activity["moving_time"]
    time_converter(total_seconds)
  end  

  def elapsed_time(activity)
    total_seconds = activity["elapsed_time"]
    time_converter(total_seconds)
  end

  def total_elevation_gain(activity)
    meters = activity["total_elevation_gain"]
    feet = (meters * meter_to_foot).round(0)
  end

  def elev_high(activity)
    meters = activity["elev_high"]
    feet = (meters * meter_to_foot).round(0)
  end

  def elev_low(activity)
    meters = activity["elev_low"]
    feet = (meters * meter_to_foot).round(0)
  end

  def average_pace(activity)
    pace_converter(activity)
  end

  def average_speed(activity)
    mps = activity["average_speed"]
    mph = (mps * mph_conversion).round(2)
  end  

  def max_speed(activity)
    mps = activity["max_speed"]
    mph = (mps * mph_conversion).round(2)
  end  

  def average_heartrate(activity)
    activity["average_heartrate"] ? activity["average_heartrate"].round(0) : "N/A"
  end  

  def max_heartrate(activity)
    activity["max_heartrate"] ? activity["max_heartrate"].round(0) : "N/A" 
  end

#----- Scoring -----#
  def score_elevation_gain(activity)
    gain_per_mile = total_elevation_gain(activity) / distance(activity)
    rating = gain_per_mile / elevation_gain_factor
  end

  def score_elevation_max(activity)
    elev_high(activity) / max_elevation_factor
  end

  def score_elevation(activity)
    elevation_score = score_elevation_gain(activity) + score_elevation_max(activity)
    elevation_score.round(2)
  end

  def score_heartrate_average(activity)
    avg_percentage = (average_heartrate(activity) - 100) / heartrate_factor #subtract 100 to intensify range, already done for heartrate factor in scoring
  end

  def score_heartrate_max(activity)
    max_percentage = max_heartrate(activity) / possible_heartrate
    (max_percentage / 2).round(2)
  end

  def score_heartrate(activity)
    if average_heartrate(activity) == "N/A"
      "N/A"
    else
      heartrate_score = score_heartrate_average(activity) + score_heartrate_max(activity)
      heartrate_score.round(2)
    end
  end

  def score_duration(activity)
    duration_score = distance(activity) / distance_factor
    duration_score.round(2)
  end

  def difficulty_rating(activity)
    if score_heartrate(activity) == "N/A"
      difficulty = score_duration(activity) + score_elevation(activity)
    else 
      difficulty = score_duration(activity) + score_heartrate(activity) + score_elevation(activity)
    end.round(2)
  end

  def difficulty_range(activity)
    score_heartrate(activity) == "N/A" ? 95 : 100
  end

  def heartrate_range(activity)
    score_heartrate(activity) == "N/A" ? "N/A" : 5
  end

  def percentage_difficulty(activity)
    percent = difficulty_rating(activity) / difficulty_range(activity)
    format_percentage(percent)
  end
  
# ----- Graphing -----#
  def start_latitude(activity)
    activity["start_latitude"]
  end

  def start_longitude(activity)
    activity["start_longitude"]
  end

  def polyline(activity)
    polyline = activity["map"]["polyline"]
    poly_arrays = Polylines::Decoder.decode_polyline(polyline)
    poly_arrays.map { |lat, lng| { lat: lat, lng: lng } }
  end

  def midpoint(activity)
    midpoint = (polyline(activity).count / 2)
    polyline(activity)[midpoint]
  end

  def midpoint_latitude(activity)
    midpoint(activity)[:lat]
  end

  def midpoint_longitude(activity)
    midpoint(activity)[:lng]
  end

end