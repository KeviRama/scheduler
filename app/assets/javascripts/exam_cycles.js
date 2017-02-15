"use strict";

//
//  Do nothing at all unless we are on the right page.
//
if ($('#examcycle').length) {

//
//  Wrap everything in a function to avoid namespace pollution
//  Note that we invoke the function immediately.
//
var examcycles = function() {

  var that = {};

  var ProtoEvent = Backbone.Model.extend({
    defaults: {
      status: "created",
      room: "",
      rota_template_name: "",
      starts_on_text: "",
      ends_on_text: "",
      event_count: 0
    }
  });

  var ProtoEventView = Backbone.View.extend({
    model: ProtoEvent,
    tagName: 'tr',
    className: 'ec-protoevent',
    template: _.template($('#ec-protoevent-row').html()),
    errortemplate: _.template($('#ec-error-msg').html()),
    initialize: function(options) {
      _.bindAll(this, 'updateError', 'updateOK');
      this.model.on('change', this.render, this);
      this.model.on('destroy', this.remove, this);
      this.owner = options.owner;
    },
    events: {
      'click .add'     : 'addProtoEvent',
      'click .edit'    : 'startEdit',
      'click .cancel'  : 'cancelEdit',
      'click .update'  : 'update',
      'click .destroy' : 'destroy'
    },
    setState: function(state) {
      this.$el.removeClass("creating");
      this.$el.removeClass("created");
      this.$el.removeClass("editing");
      this.$el.removeClass("generated");
      this.$el.addClass(state);
    },
    render: function() {
      console.log("ProtoEventView asked to render.");
//      console.log(this.template(this.model.toJSON()));
//      console.log("Currently contains: " + this.$el.html());
      this.setState(this.model.get("status"));
      this.$el.html(this.template(this.model.toJSON()));
      this.$el.find('.datepicker').datepicker({ dateFormat: "dd/mm/yy"});
      this.$el.find('.data-autocomplete').railsAutocomplete();
      return this;
    },
    destroy: function() {
      this.model.destroy();
    },
    fieldContents: function() {
      return {
        location_id:      this.$('.location_id').val(),
        rota_template_id: this.$('.inputrtname').val(),
        starts_on_text:   this.$('input.starts_on').val(),
        ends_on_text:     this.$('input.ends_on').val()
      }
    },
    clearErrorMessages: function () {
      this.$("small.error").remove();
      this.$("div.error").removeClass("error");
    },
    addProtoEvent: function() {
      //
      //  First get rid of any left over error messages and attributes.
      //
      this.clearErrorMessages();
      //
      //  The user wants to create a new proto event.  We need all
      //  4 fields to have been filled in with useful values.
      //
      //  Should be able simply to read them, and then rely on
      //  validation in both our local model, and on the server,
      //  to pick up issues.
      //
      this.owner.createNewProtoEvent(this.fieldContents(),
                                     this.creationOK,
                                     this.creationError,
                                     this);
    },
    creationOK: function() {
      console.log("Created successfully.");
    },
    creationError: function(model, response, options) {
      var view, errors;

      console.log("ProtoEvent view noting error.");
      view = this;
      errors = $.parseJSON(response.responseText);
      for (var property in errors) {
        if (errors.hasOwnProperty(property)) {
          console.log(property + ": " + errors[property]);
          var div = view.$el.find("div." + property);
          div.append(view.errortemplate({error_msg: errors[property]}));
          div.addClass("error");
        }
      }
    },
    startEdit: function() {
      this.$('.location_id').val(this.model.get('location_id'));
      this.$('.inputname').val(this.model.get('room'));
      this.$('.inputrtname').val(this.model.get('rota_template_id'));
      this.clearErrorMessages();
      this.setState("editing");
    },
    cancelEdit: function() {
      this.setState("created");
    },
    update: function() {
      this.clearErrorMessages();
      this.model.save(
          this.fieldContents(),
          {
            error: this.updateError,
            wait: true
          })
    },
    updateError: function(model, response) {
      var view, errors;

      console.log("ProtoEvent view noting update error.");
      view = this;
      errors = $.parseJSON(response.responseText);
      for (var property in errors) {
        if (errors.hasOwnProperty(property)) {
          console.log(property + ": " + errors[property]);
          var div = view.$el.find("div." + property);
          div.append(view.errortemplate({error_msg: errors[property]}));
          div.addClass("error");
        }
      }
    },
    updateOK: function(model, response) {
      this.setState("created");
    }
  });

  var ProtoEvents = Backbone.Collection.extend({
    model: ProtoEvent,
    initialize: function(models, options) {
      this.ecid = options.ecid;
    },
    comparator: function(item) {
      return item.attributes.starts_on;
    },
    url: function() {
      return '/exam_cycles/' + this.ecid + '/proto_events'
    }
  });

  var ProtoEventsView = Backbone.View.extend({
    el: '#ec-table tbody',
    initialize: function (ecid) {
      _.bindAll(this, 'addOne');
      this.collection = new ProtoEvents(null, {ecid: ecid});
      this.listenTo(this.collection, 'sync', this.render);
      this.collection.fetch();
    },
    render: function() {
      console.log("Asked to render " + this.collection.length + " proto events");
      var $list = this.$el.empty();
      this.collection.each(function(model) {
        var protoEventView = new ProtoEventView({model: model});
        $list.append(protoEventView.render().$el);
      }, this);
      return this;
    },
    addOne: function(params, success, failure, object) {
      var newProtoEvent = this.collection.create(
        params,
        {
          wait: true
        }).on('sync', success, object).on('error', failure, object);
    },
  });

  var ExamCycle = Backbone.Model.extend({
    urlRoot: '/exam_cycles'
  });

  var ExamCycleView = Backbone.View.extend({
    el: "#ec-table",
    model: ExamCycle,
    initialize: function(rtid) {
      this.model = new ExamCycle({id: rtid});
      this.listenTo(this.model, 'sync', this.render);
      this.$forentry = this.$('tfoot tr')
      this.model.fetch();
      //
      //  We also need a dummy ProtoEvent which will handle our
      //  input fields in the bottom row.
      //
      this.newPE = new ProtoEvent({
        status: "creating",
        id: ""
      });
      this.newPEView = new ProtoEventView({
        model: this.newPE,
        el: this.$forentry,
        owner: this
      });
    },
    render: function() {
      console.log("ExamCycleView asked to render.");
      //
      //  Nothing actually to render of the cycle itself, but
      //  we do need to set up the input fields in the footer.
      //
      this.newPE.set("starts_on_text", this.model.get("starts_on_text"));
      this.newPE.set("ends_on_text", this.model.get("ends_on_text"));
      this.newPEView.render();
      return this;
    },
    createNewProtoEvent: function(params, success, failure, object) {
      console.log("Asked to create a new ProtoEvent.");
      that.protoEventsView.addOne(params, success, failure, object);
    }
  });

  function getExamCycle(ecid) {
    var examCycleView = new ExamCycleView(ecid);
  };

  function getProtoEvents(ecid) {
    that.protoEventsView = new ProtoEventsView(ecid);
  };

  that.init = function() {
    //
    //  We have already checked that our master parent division
    //  exists, otherwise we wouldn't be running at all.
    //
    var ecid = $('#examcycle').data("ecid");
    getExamCycle(ecid);
    getProtoEvents(ecid);
  }

  return that;

}();

//
//  Once the DOM is ready, get our code to initialise itself.
//
$(examcycles.init);

}
