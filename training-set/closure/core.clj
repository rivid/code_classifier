(ns soy-clj.core
  "An idiomatic Clojure wrapper for Google Closure templates."
  (:require [clojure.core.cache :as cache]
            [clojure.java.io :as io]
            [clojure.set :as set]
            [clojure.string :as string]
            [clojure.walk :as walk])
  (:import (com.google.template.soy SoyFileSet SoyFileSet$Builder)
           (com.google.template.soy.data SanitizedContent$ContentKind
                                         UnsafeSanitizedContentOrdainer)
           (com.google.template.soy.shared SoyGeneralOptions)
           (com.google.template.soy.tofu SoyTofu)))

(def ^:private template-cache
  "Default to keeping the 32 most-used templates in cache."
  (atom (cache/lu-cache-factory {})))

(defn set-cache
  "Sets the cache for parsed templates."
  [cache]
  (reset! template-cache cache))

(def ^:private opts
  "Default to requiring autoescaped templates."
  (doto (SoyGeneralOptions.)
    (.setStrictAutoescapingRequired true)))

(defn- parse-uncached
  "Returns a compiled set of templates from the given files."
  [files]
  (let [builder (SoyFileSet/builder)]
    (run! #(.add builder (io/file (io/resource %))) files)
    (.setGeneralOptions builder opts)
    (.. builder (build) (compileToTofu))))

(defn parse
  "Given the filename (or a sequence of filenames) of a Closure template on the
  classpath, parses the templates and returns a compiled set of templates."
  [file-or-files]
  (let [files (vec (flatten (vector file-or-files)))]
    (if-let [found (cache/lookup @template-cache files)]
      found
      (let [templates (parse-uncached files)]
        (swap! template-cache assoc files templates)
        templates))))

(defn- camel-case
  "Converts a symbol like `:blah-blah` into a string like `blahBlah`."
  [s]
  (let [ss (string/split (name s) #"-")]
    (string/join (cons (string/lower-case (first ss))
                       (map string/capitalize (next ss))))))

(defn- camelize-keys
  "Recursively transforms a map, converting all keyword keys into camel-case
  strings."
  ^java.util.Map [m]
  (let [f (fn [[k v]] (if (keyword? k) [(camel-case k) v] [k v]))]
    (walk/postwalk (fn [x] (if (map? x) (into {} (map f x)) x)) m)))

(defn content-type
  "The MIME content-type of the given kind."
  [kind]
  (case kind
    :css "text/css; charset=utf-8"
    :html "text/html; charset=utf-8"
    :js "text/javascript; charset=utf-8"
    "text/plain; charset=utf-8"))

(def ^:private content-kind
  "A map of ContentKind enums to happy little symbols."
  {SanitizedContent$ContentKind/ATTRIBUTES :attributes
   SanitizedContent$ContentKind/CSS :css
   SanitizedContent$ContentKind/HTML :html
   SanitizedContent$ContentKind/JS :js
   SanitizedContent$ContentKind/TEXT :text
   SanitizedContent$ContentKind/URI :uri})

(def ^:private content-kind-enum
  "A map of happy little symbols to ContentKind enums."
  (set/map-invert content-kind))

(defn render
  "Given a parsed set of templates, renders the named template with the given
  data and returns the result as a string as well as the _kind_ of data in the
  template (e.g. `:html`). Data keys of the form `:one-two` are converted into
  template variables of the form `oneTwo`."
  [^SoyTofu templates ^String template-name data]
  (let [content (.. templates
                    (newRenderer template-name)
                    (setData (camelize-keys data))
                    (renderStrict))]
    [(.getContent content) (content-kind (.getContentKind content))]))

(defn ordain-as-safe
  "Ordains the given content as safe content of the given kind which will not be
  escaped inside that kind's context. Use this sparingly, as it entirely
  bypasses Soy's XSS protection."
  [content kind]
  (UnsafeSanitizedContentOrdainer/ordainAsSafe content
                                               (content-kind-enum kind)))