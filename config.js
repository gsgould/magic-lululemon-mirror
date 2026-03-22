/* MagicMirror config for Lululemon Mirror (portrait mode)
 *
 * Modules: clock, compliments
 * Layout optimized for a tall, narrow mirror display.
 */

let config = {
	address: "0.0.0.0",
	port: 8080,
	basePath: "/",
	ipWhitelist: [],
	language: "en",
	locale: "en-US",
	timeFormat: 12,
	units: "metric",

	modules: [
		// --- Top bar: Clock ---
		{
			module: "clock",
			position: "top_center",
			config: {
				dateFormat: "dddd, MMMM D",
				showSunTimes: false,
				showWeek: false,
			}
		},

		// --- Middle: Workout prompt ---
		{
			module: "compliments",
			position: "upper_third",
			classes: "workout-prompt",
			header: "Open up your screen casting and select \"Mirror\" to start your session.",
			config: {
				compliments: {
					anytime: [
						"Hey Greg, ready to workout?",
					],
				}
			}
		},

		// --- Lower third: Compliments ---
		{
			module: "compliments",
			position: "lower_third",
			config: {
				compliments: {
					anytime: [
						"You look great today!",
						"Keep going, you're doing amazing.",
						"Stay strong.",
					],
					morning: [
						"Good morning!",
						"Rise and shine!",
						"Today is a new opportunity.",
					],
					afternoon: [
						"Keep up the great work!",
						"You're crushing it today.",
					],
					evening: [
						"Time to wind down.",
						"You earned this rest.",
						"Great job today!",
					],
				}
			}
		},
	]
};

/*************** DO NOT EDIT THE LINE BELOW ***************/
if (typeof module !== "undefined") { module.exports = config; }
