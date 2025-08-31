[
  import_deps: [
    :ash,
    :spark
  ],
  plugins: [Spark.Formatter],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"]
]
